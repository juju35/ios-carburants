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
    private let fuelTemplate = CPListTemplate(title: "Carburants", sections: [])

    // The point-of-interest template shows at most 12 places.
    private static let maxPoints = 12

    init(interface: CPInterfaceController, scene: CPTemplateApplicationScene) {
        self.interface = interface
        self.scene = scene
        super.init()
    }

    func start() {
        mapTemplate.pointOfInterestDelegate = self
        mapTemplate.tabTitle = "Carte"
        mapTemplate.tabImage = UIImage(systemName: "map.fill")
        listTemplate.tabTitle = "Liste"
        listTemplate.tabImage = UIImage(systemName: "list.bullet")
        fuelTemplate.tabTitle = "Carburants"
        fuelTemplate.tabImage = UIImage(systemName: "fuelpump.fill")

        let tabs = CPTabBarTemplate(templates: [mapTemplate, listTemplate, fuelTemplate])
        interface.setRootTemplate(tabs, animated: false, completion: nil)
        model.start()
        model.resume()
        observe()
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
        _ = LogoStore.shared.revision

        let points = stations.prefix(Self.maxPoints).map { point($0) }
        mapTemplate.setPointsOfInterest(points, selectedIndex: NSNotFound)

        let items = stations.prefix(CPListTemplate.maximumItemCount).map { listItem($0) }
        listTemplate.updateSections([CPListSection(items: items)])
        listTemplate.emptyViewTitleVariants = [emptyTitle]
        listTemplate.emptyViewSubtitleVariants = [emptySubtitle]
        let sort = CPBarButton(title: model.sort == .price ? "Prix" : "Distance") { [weak self] _ in
            guard let self else { return }
            model.setSort(model.sort == .price ? .distance : .price)
        }
        listTemplate.trailingNavigationBarButtons = [sort]

        let fuelItems = Fuel.allCases.map { fuel in
            let item = CPListItem(
                text: fuel.label,
                detailText: fuel.summary,
                image: image(FuelBadge(fuel, large: true)),
                accessoryImage: fuels.contains(fuel) ? UIImage(systemName: "checkmark") : nil,
                accessoryType: .none
            )
            item.handler = { [weak self] _, completion in
                self?.model.toggleFuel(fuel)
                completion()
            }
            return item
        }
        fuelTemplate.updateSections([
            CPListSection(items: fuelItems, header: "Carburants de votre véhicule", sectionIndexTitle: nil),
        ])
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
        let item = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate))
        item.name = station.name
        let prices = priceLine(station, fuels: fuels)
        let place = [station.distanceKm.map(Format.distance), Opening.of(station)?.text].compactMap { $0 }.joined(separator: " · ")
        let point = CPPointOfInterest(
            location: item,
            title: station.name,
            subtitle: prices,
            summary: place,
            detailTitle: station.name,
            detailSubtitle: prices,
            detailSummary: "\(station.prettyAddress), \(station.prettyCity)\n\(place)",
            pinImage: image(StationLogo(station, size: 32).overlay { cheapestRing(station, size: 32) })
        )
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
        let item = CPListItem(text: station.name, detailText: detail, image: image(StationLogo(station, size: 44)))
        item.accessoryType = .disclosureIndicator
        item.handler = { [weak self] _, completion in
            self?.showDetail(station)
            completion()
        }
        return item
    }

    /// "1,689 €" with one fuel; "Gazole 1,689 €" with several.
    private func priceLine(_ station: Station, fuels: [Fuel]) -> String {
        guard let best = station.best(fuels) else { return station.sellsAny(fuels) ? "Rupture" : "Prix indisponible" }
        return fuels.count > 1 ? "\(best.fuel.short) \(Format.price(best.price))" : Format.price(best.price)
    }

    private func showDetail(_ station: Station) {
        var items: [CPInformationItem] = Fuel.allCases.filter { station.sells($0) }.map { fuel in
            let value = station.fuels[fuel]
            let detail: String = if let price = station.price(fuel) {
                value?.updated.map { "\(Format.price(price)) · \(Format.ago($0))" } ?? Format.price(price)
            } else {
                "Rupture"
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

    /// Hands the destination to Plans, which takes over the CarPlay screen.
    private func navigate(to station: Station) {
        guard let url = URL(string: "maps://?daddr=\(station.latitude),\(station.longitude)&dirflg=d") else { return }
        scene?.open(url, options: nil, completionHandler: nil)
    }

    // MARK: - Images

    @ViewBuilder
    private func cheapestRing(_ station: Station, size: CGFloat) -> some View {
        if model.isCheapest(station) {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(.green, lineWidth: 3)
        }
    }

    private func image(_ view: some View) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = interface.carTraitCollection.displayScale
        return renderer.uiImage
    }

    // MARK: - CPPointOfInterestTemplateDelegate

    nonisolated func pointOfInterestTemplate(_ template: CPPointOfInterestTemplate, didChangeMapRegion region: MKCoordinateRegion) {}
}
