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
    /// The place the driver opened on the map, kept selected across rebuilds.
    private var selectedID: Station.ID?
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
        fuelTemplate.tabTitle = "Réglages"
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

    func sceneWillEnterForeground() {
        if model.customLocation != nil {
            model.resetToCurrentLocation()
        }
        model.resume()
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
        if fuels != pickerFuels || currentNavApp != pickerNavigationApp {
            pickerFuels = fuels
            pickerNavigationApp = currentNavApp
            let fuelItems = Fuel.allCases.map { fuelItem($0, chosen: fuels.contains($0)) }
            let navItems = availableNavigationApps().map { navigationItem($0, chosen: currentNavApp == $0) }
            fuelTemplate.updateSections([
                CPListSection(items: fuelItems, header: "Carburants de votre véhicule", sectionIndexTitle: nil),
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
        point.primaryButton = CPTextButton(title: "Y aller", textStyle: .confirm) { [weak self] _ in
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

        let go = CPTextButton(title: "Y aller", textStyle: .confirm) { [weak self] _ in self?.navigate(to: station) }
        let template = CPInformationTemplate(
            title: station.name, layout: .twoColumn, items: Array(items.prefix(10)), actions: [go]
        )
        interface.pushTemplate(template, animated: true, completion: nil)
    }

    /// Prompts the driver to choose which navigation app to open (or opens the single one), then launches it.
    private func navigate(to station: Station) {
        let apps = availableNavigationApps()
        if apps.count <= 1 {
            openNavigationApp(apps.first ?? .appleMaps, for: station)
            return
        }

        var actions: [CPAlertAction] = apps.map { app in
            CPAlertAction(title: app.title, style: .default) { [weak self] _ in
                self?.model.setNavigationApp(app)
                self?.openNavigationApp(app, for: station)
            }
        }
        actions.append(CPAlertAction(title: "Annuler", style: .cancel) { [weak self] _ in
            self?.interface.dismissTemplate(animated: true, completion: nil)
        })

        let actionSheet = CPActionSheetTemplate(
            title: "Itinéraire",
            message: station.name,
            actions: actions
        )
        interface.presentTemplate(actionSheet, animated: true, completion: nil)
    }

    private func availableNavigationApps() -> [NavigationApp] {
        var apps: [NavigationApp] = [.appleMaps]
        if let gmaps = URL(string: "comgooglemaps://"), UIApplication.shared.canOpenURL(gmaps) {
            apps.append(.googleMaps)
        }
        if let waze = URL(string: "waze://"), UIApplication.shared.canOpenURL(waze) {
            apps.append(.waze)
        }
        return apps
    }

    private func openNavigationApp(_ app: NavigationApp, for station: Station) {
        let url = app.url(for: station)
        scene?.open(url, options: nil, completionHandler: nil)
    }

    // MARK: - Images

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

    // MARK: - CPPointOfInterestTemplateDelegate

    nonisolated func pointOfInterestTemplate(_ template: CPPointOfInterestTemplate, didChangeMapRegion region: MKCoordinateRegion) {}

    nonisolated func pointOfInterestTemplate(
        _ template: CPPointOfInterestTemplate, didSelectPointOfInterest pointOfInterest: CPPointOfInterest
    ) {
        let id = pointOfInterest.userInfo as? Station.ID
        Task { @MainActor in
            self.selectedID = id
        }
    }
}
