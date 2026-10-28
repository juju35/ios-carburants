import CarburantsKit
import CarPlay
import MapKit
import Observation
import SwiftUI

/// CarPlay screens, built from the same model as the iPhone: a map of the stations (point-of-interest template,
/// as the Fueling category asks), the list sorted by price or distance, and the fuel picker.
@MainActor
final class CarPlayController: NSObject, CPPointOfInterestTemplateDelegate {
    private let interface: CPInterfaceController
    private weak var scene: CPTemplateApplicationScene?
    private let model = StationsModel.shared

    private let mapTemplate = CPPointOfInterestTemplate(title: "À proximité", pointsOfInterest: [], selectedIndex: NSNotFound)
    private let listTemplate = CPListTemplate(title: "Stations", sections: [])
    private let fuelTemplate = CPListTemplate(title: "Réglages", sections: [])

    // The point-of-interest template shows at most 12 places.
    private static let maxPoints = 12

    /// What a template was last built from: it is rebuilt only when that changes, so a refresh that changes nothing
    /// on screen neither redraws the images nor closes the place card or scrolls the list back up.
    private struct Content: Equatable {
        let stations: [Station]
        let fuels: [Fuel]
        let cheapest: Double?
        let logos: Int
    }

    private var pointsContent: Content?
    private var listContent: Content?
    private var listStatus: [String]?
    private var listSort: StationOrder?
    private var pickerFuels: [Fuel]?
    private var pickerNavigationApp: NavigationApp?
    private var pickerRadiusKm: Int?
    /// The place the driver opened on the map, kept selected across rebuilds.
    private var selectedID: Station.ID?
    /// Travel times by car shown on the "Y aller" buttons, as on the iPhone; refreshed when older than 2 minutes.
    private var travelTimes: [Station.ID: (eta: TimeInterval, date: Date)] = [:]
    private var pendingETAs: Set<Station.ID> = []
    /// Rendered logos and badges, by station or fuel; emptied when downloaded logos arrive.
    private var images: [String: UIImage] = [:]
    private var imagesRevision = -1
    private var lastDisplayScale: CGFloat = 0

    init(interface: CPInterfaceController, scene: CPTemplateApplicationScene) {
        self.interface = interface
        self.scene = scene
        super.init()
    }

    func start() {
        if model.customLocation != nil {
            model.resetToCurrentLocation()
        }
        mapTemplate.pointOfInterestDelegate = self
        mapTemplate.tabTitle = "Carte"
        mapTemplate.tabImage = UIImage(systemName: "map.fill")
        listTemplate.tabTitle = "Liste"
        listTemplate.tabImage = UIImage(systemName: "list.bullet")
        // The tab bar shows titles only (iOS 26): a gear in text presentation keeps the tab short.
        fuelTemplate.tabTitle = "\u{2699}\u{FE0E}"
        fuelTemplate.tabImage = UIImage(systemName: "gearshape.fill")

        let tabs = CPTabBarTemplate(templates: [mapTemplate, listTemplate, fuelTemplate])
        interface.setRootTemplate(tabs, animated: false, completion: nil)
        model.start()
        model.resume()
        observe()
    }

    func sceneDidBecomeActive() {
        if model.customLocation != nil {
            model.resetToCurrentLocation()
        }
        model.resume()
        let scale = currentDisplayScale()
        if scale != lastDisplayScale {
            images.removeAll()
            lastDisplayScale = scale
            pointsContent = nil
            listContent = nil
            render()
        }
    }

    /// Renders now, and again after any change to what was read (until the scene goes and this controller with it).
    private func observe() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    // MARK: - Templates

    private func render() {
        let stations = model.visible
        let fuels = model.fuels
        let cheapest = model.cheapestPrice
        let revision = LogoStore.shared.revision
        let sort = model.sort
        let status = [emptyTitle, emptySubtitle]
        let currentScale = currentDisplayScale()
        if currentScale != lastDisplayScale {
            images.removeAll()
            lastDisplayScale = currentScale
            pointsContent = nil
            listContent = nil
        }
        if revision != imagesRevision {
            images.removeAll()
            imagesRevision = revision
        }

        let shownPoints = Content(stations: Array(stations.prefix(Self.maxPoints)), fuels: fuels, cheapest: cheapest, logos: revision)
        if shownPoints != pointsContent {
            pointsContent = shownPoints
            let selected = shownPoints.stations.firstIndex { $0.id == selectedID } ?? NSNotFound
            mapTemplate.setPointsOfInterest(shownPoints.stations.map { point($0) }, selectedIndex: selected)
        }

        let shownList = Content(
            stations: Array(stations.prefix(CPListTemplate.maximumItemCount)), fuels: fuels, cheapest: cheapest, logos: revision
        )
        if shownList != listContent {
            listContent = shownList
            listTemplate.updateSections([CPListSection(items: shownList.stations.map { listItem($0) })])
        }
        if status != listStatus {
            listStatus = status
            listTemplate.emptyViewTitleVariants = [status[0]]
            listTemplate.emptyViewSubtitleVariants = [status[1]]
        }
        if sort != listSort {
            listSort = sort
            let button = CPBarButton(title: sort == .price ? "Prix" : "Distance") { [weak self] _ in
                guard let self else { return }
                model.setSort(model.sort == .price ? .distance : .price)
            }
            listTemplate.trailingNavigationBarButtons = [button]
        }

        let currentNavApp = model.navigationApp
        let currentRadius = model.searchRadiusKm
        if fuels != pickerFuels || currentNavApp != pickerNavigationApp || currentRadius != pickerRadiusKm {
            pickerFuels = fuels
            pickerNavigationApp = currentNavApp
            pickerRadiusKm = currentRadius
            let fuelItems = Fuel.allCases.map { fuelItem($0, chosen: fuels.contains($0)) }
            let radiusItems = Preferences.radiusChoices.map { radiusItem($0, chosen: currentRadius == $0) }
            let navItems = availableNavigationApps().map { navigationItem($0, chosen: currentNavApp == $0) }
            fuelTemplate.updateSections([
                CPListSection(items: fuelItems, header: "Carburants de votre véhicule", sectionIndexTitle: nil),
                CPListSection(items: radiusItems, header: "Rayon de recherche", sectionIndexTitle: nil),
                CPListSection(items: navItems, header: "Application de navigation", sectionIndexTitle: nil),
            ])
        }
    }

    private func fuelItem(_ fuel: Fuel, chosen: Bool) -> CPListItem {
        let item = CPListItem(
            text: fuel.label,
            detailText: fuel.summary,
            image: cachedImage("fuel-\(fuel.rawValue)") { FuelBadge(fuel, large: true) },
            accessoryImage: chosen ? UIImage(systemName: "checkmark") : nil,
            accessoryType: .none
        )
        item.handler = { [weak self] _, completion in
            self?.model.toggleFuel(fuel)
            completion()
        }
        return item
    }

    private func radiusItem(_ radius: Int, chosen: Bool) -> CPListItem {
        let item = CPListItem(
            text: "\(radius) km",
            detailText: nil,
            image: UIImage(systemName: "location.circle"),
            accessoryImage: chosen ? UIImage(systemName: "checkmark") : nil,
            accessoryType: .none
        )
        item.handler = { [weak self] _, completion in
            self?.model.setSearchRadius(radius)
            completion()
        }
        return item
    }

    private func navigationItem(_ app: NavigationApp, chosen: Bool) -> CPListItem {
        let item = CPListItem(
            text: app.title,
            detailText: nil,
            image: UIImage(systemName: app.symbol),
            accessoryImage: chosen ? UIImage(systemName: "checkmark") : nil,
            accessoryType: .none
        )
        item.handler = { [weak self] _, completion in
            self?.model.setNavigationApp(app)
            completion()
        }
        return item
    }

    private var emptyTitle: String {
        let location = model.location
        if location.isDenied || location.authorization == .notDetermined { return "Localisation non autorisée" }
        if model.stations == nil, case .failed = model.phase { return "Prix indisponibles" }
        if model.stations == nil { return "Recherche des stations…" }
        return "Aucune station"
    }

    private var emptySubtitle: String {
        let location = model.location
        if location.isDenied || location.authorization == .notDetermined { return "Autorisez-la dans l’app Carburants sur l’iPhone." }
        if model.stations == nil, case let .failed(message) = model.phase { return message }
        if model.stations == nil { return "" }
        return "Aucune station \(Format.fuels(model.fuels)) dans un rayon de \(model.radiusKm) km."
    }

    private func point(_ station: Station) -> CPPointOfInterest {
        let fuels = model.fuels
        let item: MKMapItem
        if #available(iOS 26, *) {
            item = MKMapItem(location: CLLocation(latitude: station.latitude, longitude: station.longitude), address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate))
        }
        item.name = station.name
        let prices = priceLine(station, fuels: fuels)
        let place = [station.distanceKm.map(Format.distance), Opening.of(station)?.text].compactMap { $0 }.joined(separator: " · ")

        let pinSize = CPPointOfInterest.pinImageSize.width > 0 ? CPPointOfInterest.pinImageSize.width : 40
        let selectedPinSize = CPPointOfInterest.selectedPinImageSize.width > 0 ? CPPointOfInterest.selectedPinImageSize.width : 48

        let pin = cachedImage("pin-\(station.id)-\(model.isCheapest(station))-\(Int(pinSize))") {
            StationLogo(station, size: pinSize).overlay { cheapestRing(station, size: pinSize) }
        }
        let selectedPin = cachedImage("pin-selected-\(station.id)-\(model.isCheapest(station))-\(Int(selectedPinSize))") {
            StationLogo(station, size: selectedPinSize).overlay { cheapestRing(station, size: selectedPinSize) }
        }

        let point = CPPointOfInterest(
            location: item,
            title: station.name,
            subtitle: prices,
            summary: place,
            detailTitle: station.name,
            detailSubtitle: prices,
            detailSummary: "\(station.prettyAddress), \(station.prettyCity)\n\(place)",
            pinImage: pin,
            selectedPinImage: selectedPin
        )
        point.userInfo = station.id
        point.primaryButton = CPTextButton(title: goTitle(for: station), textStyle: .confirm) { [weak self] _ in
            self?.navigate(to: station)
        }
        point.secondaryButton = CPTextButton(title: "Détails", textStyle: .normal) { [weak self] _ in
            self?.showDetail(station)
        }
        return point
    }

    private func listItem(_ station: Station) -> CPListItem {
        let detail = [priceLine(station, fuels: model.fuels), station.distanceKm.map(Format.distance), Opening.of(station)?.text]
            .compactMap { $0 }
            .joined(separator: " · ")
        let item = CPListItem(
            text: station.name, detailText: detail, image: cachedImage("row-\(station.id)") { StationLogo(station, size: 44) }
        )
        item.accessoryType = .disclosureIndicator
        item.handler = { [weak self] _, completion in
            self?.showDetail(station)
            completion()
        }
        return item
    }

    /// "1,689 €" with one fuel; "Gazole 1,689 €" with several.
    private func priceLine(_ station: Station, fuels: [Fuel]) -> String {
        guard let best = station.best(fuels) else { return station.inShortage(fuels) ? "Rupture" : "Prix indisponible" }
        return fuels.count > 1 ? "\(best.fuel.short) \(Format.price(best.price))" : Format.price(best.price)
    }

    private func showDetail(_ station: Station) {
        var items: [CPInformationItem] = Fuel.allCases.filter { station.sells($0) }.map { fuel in
            let value = station.fuels[fuel]
            let detail: String = if let price = station.price(fuel) {
                value?.updated.map { "\(Format.price(price)) · \(Format.ago($0))" } ?? Format.price(price)
            } else if value?.rupture != nil {
                "Rupture"
            } else {
                "Prix indisponible"
            }
            return CPInformationItem(title: model.fuels.contains(fuel) ? "\(fuel.label) ★" : fuel.label, detail: detail)
        }
        items.append(CPInformationItem(title: "Adresse", detail: "\(station.prettyAddress), \(station.postcode) \(station.prettyCity)"))
        if let opening = Opening.of(station) { items.append(CPInformationItem(title: "Horaires", detail: opening.text)) }
        if let distance = station.distanceKm { items.append(CPInformationItem(title: "Distance", detail: Format.distance(distance))) }

        let go = CPTextButton(title: goTitle(for: station), textStyle: .confirm) { [weak self] _ in self?.navigate(to: station) }
        let template = CPInformationTemplate(
            title: station.name, layout: .twoColumn, items: Array(items.prefix(10)), actions: [go]
        )
        interface.pushTemplate(template, animated: true, completion: nil)
        loadTravelTimeIfNeeded(for: station) { [weak self, weak template] in
            guard let self, let template else { return }
            template.actions = [
                CPTextButton(title: self.goTitle(for: station), textStyle: .confirm) { [weak self] _ in
                    self?.navigate(to: station)
                }
            ]
        }
    }

    // MARK: - CPPointOfInterestTemplateDelegate

    nonisolated func pointOfInterestTemplate(_ template: CPPointOfInterestTemplate, didChangeMapRegion region: MKCoordinateRegion) {}

    nonisolated func pointOfInterestTemplate(
        _ template: CPPointOfInterestTemplate, didSelectPointOfInterest pointOfInterest: CPPointOfInterest
    ) {
        let id = pointOfInterest.userInfo as? Station.ID
        Task { @MainActor in
            self.selectedID = id
            // The "Y aller" button is visible once the place is selected: fetch its travel time now.
            guard let id, let station = self.pointsContent?.stations.first(where: { $0.id == id }) else { return }
            self.loadTravelTimeIfNeeded(for: station) { [weak self = self] in
                self?.pointsContent = nil
                self?.render()
            }
        }
    }
}

// MARK: - Directions

extension CarPlayController {
    /// Opens the navigation app chosen in the settings, without asking; Plans when it is not installed.
    func navigate(to station: Station) {
        let preferred = model.navigationApp
        let app = availableNavigationApps().contains(preferred) ? preferred : .appleMaps
        scene?.open(app.url(for: station), options: nil, completionHandler: nil)
    }

    func availableNavigationApps() -> [NavigationApp] {
        var apps: [NavigationApp] = [.appleMaps]
        if let gmaps = URL(string: "comgooglemaps://"), UIApplication.shared.canOpenURL(gmaps) {
            apps.append(.googleMaps)
        }
        if let waze = URL(string: "waze://"), UIApplication.shared.canOpenURL(waze) {
            apps.append(.waze)
        }
        return apps
    }

    /// "Y aller", with the travel time once known, as on the iPhone button.
    func goTitle(for station: Station) -> String {
        guard let eta = travelTime(for: station) else { return "Y aller" }
        return "Y aller · \(Format.duration(eta))"
    }

    private func travelTime(for station: Station) -> TimeInterval? {
        guard let cached = travelTimes[station.id], Date.now.timeIntervalSince(cached.date) < 120 else { return nil }
        return cached.eta
    }

    /// Fetches the ETA once per station (then every 2 minutes), and calls `onUpdate` when it lands.
    func loadTravelTimeIfNeeded(for station: Station, onUpdate: @escaping @MainActor () -> Void) {
        guard travelTime(for: station) == nil, !pendingETAs.contains(station.id) else { return }
        pendingETAs.insert(station.id)
        Task { [weak self] in
            let request = MKDirections.Request()
            request.source = .forCurrentLocation()
            request.destination = Directions.mapItem(for: station)
            request.transportType = .automobile
            let response = try? await MKDirections(request: request).calculateETA()
            guard let self else { return }
            self.pendingETAs.remove(station.id)
            guard let response else { return }
            self.travelTimes[station.id] = (response.expectedTravelTime, .now)
            onUpdate()
        }
    }
}

// MARK: - Images

extension CarPlayController {
    @ViewBuilder
    private func cheapestRing(_ station: Station, size: CGFloat) -> some View {
        if model.isCheapest(station) {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(.green, lineWidth: 3)
        }
    }

    private func currentDisplayScale() -> CGFloat {
        let scale = interface.carTraitCollection.displayScale
        if scale > 0 { return scale }
        if let window = scene?.carWindow, window.screen.scale > 0 {
            return window.screen.scale
        }
        return 2.0
    }

    private func cachedImage<Picture: View>(_ key: String, _ view: () -> Picture) -> UIImage? {
        if let image = images[key] { return image }
        let renderer = ImageRenderer(content: view())
        renderer.scale = currentDisplayScale()
        guard let image = renderer.uiImage?.withRenderingMode(.alwaysOriginal) else { return nil }
        images[key] = image
        return image
    }
}
