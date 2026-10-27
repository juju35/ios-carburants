import AppIntents
import CarburantsKit
import CoreLocation
import WidgetKit

/// Fuel selection in widget configuration.
enum WidgetFuel: String, AppEnum {
    case gazole, sp95, sp98, e10, e85, gplc

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Carburant"
    static let caseDisplayRepresentations: [WidgetFuel: DisplayRepresentation] = [
        .gazole: "Gazole",
        .sp95: "SP95",
        .sp98: "SP98",
        .e10: "SP95-E10",
        .e85: "E85",
        .gplc: "GPLc",
    ]

    var fuel: Fuel {
        Fuel(rawValue: rawValue) ?? .gazole
    }
}

/// Sorting order in widget configuration.
enum WidgetSort: String, AppEnum {
    case app, price, distance

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tri"
    static let caseDisplayRepresentations: [WidgetSort: DisplayRepresentation] = [
        .app: "Selon l’application",
        .price: "Prix le plus bas",
        .distance: "Distance",
    ]

    func resolved(fallback: StationOrder) -> StationOrder {
        switch self {
        case .app: return fallback
        case .price: return .price
        case .distance: return .distance
        }
    }
}

struct StationsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Stations à proximité"
    // swiftlint:disable:next unused_declaration - shown by the system in the widget's settings
    static let description = IntentDescription("Les stations autour de vous, avec leur prix.")

    @Parameter(title: "Utiliser mes carburants", default: true)
    var useAppFuels: Bool

    @Parameter(title: "Carburants")
    var customFuels: [WidgetFuel]?

    @Parameter(title: "Trier par", default: .app)
    var sort: WidgetSort

    static var parameterSummary: some ParameterSummary {
        When(\.$useAppFuels, .equalTo, false) {
            Summary {
                \.$useAppFuels
                \.$customFuels
                \.$sort
            }
        } otherwise: {
            Summary {
                \.$useAppFuels
                \.$sort
            }
        }
    }

    var resolvedFuels: [Fuel] {
        if useAppFuels {
            return Preferences.shared.fuels
        }
        let list = (customFuels ?? []).map(\.fuel)
        return list.isEmpty ? Preferences.shared.fuels : list
    }

    var resolvedSort: StationOrder {
        sort.resolved(fallback: Preferences.shared.sort)
    }
}

struct StationsEntry: TimelineEntry {
    enum State {
        case ready, noLocation, failed
    }

    let date: Date
    let fuels: [Fuel]
    let stations: [Station]
    let order: StationOrder
    let state: State
    /// When the prices were fetched (an older list is shown when offline).
    let updated: Date

    /// The same stations, shown from `date` on.
    func at(_ date: Date) -> StationsEntry {
        StationsEntry(date: date, fuels: fuels, stations: stations, order: order, state: state, updated: updated)
    }

    func isCheapest(price: Double, for fuel: Fuel) -> Bool {
        guard let lowest = stations.compactMap({ $0.price(fuel) }).min() else { return false }
        return price <= lowest
    }

    static let sample: StationsEntry = {
        let fuels: [Fuel] = [.gazole, .e10]
        let sort = Preferences.shared.sort
        return StationsEntry(
            date: .now, fuels: fuels,
            stations: StationSort.sorted(Station.samples, by: sort, fuels: fuels),
            order: sort, state: .ready, updated: .now
        )
    }()
}

@MainActor
private final class WidgetLocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func fetchCoordinate() async -> CLLocationCoordinate2D? {
        guard manager.isAuthorizedForWidgetUpdates else { return nil }

        // If manager has a very recent fix (< 60s), use it immediately without waiting:
        if let location = manager.location, -location.timestamp.timeIntervalSinceNow < 60 {
            return location.coordinate
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, let cont = self.continuation else { return }
                self.continuation = nil
                cont.resume(returning: self.manager.location?.coordinate)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coord = locations.last?.coordinate
        Task { @MainActor in
            guard let cont = self.continuation else { return }
            self.continuation = nil
            cont.resume(returning: coord)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard let cont = self.continuation else { return }
            self.continuation = nil
            cont.resume(returning: self.manager.location?.coordinate)
        }
    }
}

struct StationsProvider: AppIntentTimelineProvider {
    // Prices change every 10 minutes at most; WidgetKit spaces reloads out anyway.
    private static let refresh: TimeInterval = 30 * 60
    private static let maxStations = 12

    func placeholder(in context: Context) -> StationsEntry { .sample }

    func snapshot(for configuration: StationsIntent, in context: Context) async -> StationsEntry {
        if context.isPreview { return .sample }
        return await load(fuels: configuration.resolvedFuels, sort: configuration.resolvedSort)
    }

    func timeline(for configuration: StationsIntent, in context: Context) async -> Timeline<StationsEntry> {
        let entry = await load(fuels: configuration.resolvedFuels, sort: configuration.resolvedSort)
        return Timeline(entries: Self.entries(from: entry), policy: .after(.now.addingTimeInterval(Self.refresh)))
    }

    /// The entry again at each minute an opening status changes before the next reload ("ferme à 21:00" turns to
    /// "Fermé" at 21:00 without waiting for WidgetKit's next reload).
    static func entries(from entry: StationsEntry) -> [StationsEntry] {
        var entries = [entry]
        var shown = entry.stations.map { Opening.of($0, at: entry.date) }
        for minute in stride(from: 60.0, to: refresh, by: 60) {
            let date = entry.date.addingTimeInterval(minute)
            let now = entry.stations.map { Opening.of($0, at: date) }
            if now != shown {
                entries.append(entry.at(date))
                shown = now
            }
        }
        return entries
    }

    private func load(fuels: [Fuel], sort: StationOrder) async -> StationsEntry {
        guard let location = await currentLocation() else {
            return StationsEntry(date: .now, fuels: fuels, stations: [], order: sort, state: .noLocation, updated: .now)
        }
        do {
            // The names file is too big for the extension's memory: names, brands and logos the app found instead.
            let result = try await StationRepository.shared.nearby(
                latitude: location.latitude, longitude: location.longitude, fuels: fuels, withNamesFile: false
            )
            let known = Dictionary((Snapshot.load()?.stations ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let named = result.stations.map { station in
                guard let app = known[station.id] else { return station }
                var station = station
                station.name = app.name
                station.brand = app.brand
                station.logoURL = app.logoURL ?? station.logoURL
                return station
            }
            let stations = Array(StationSort.sorted(named, by: sort, fuels: fuels).prefix(Self.maxStations))
            await LogoStore.shared.preload(stations, timeout: 5)
            WidgetStations.save(stations)
            return StationsEntry(date: .now, fuels: fuels, stations: stations, order: sort, state: .ready, updated: .now)
        } catch {
            // Offline: the app's last list when it was for these fuels.
            if let snapshot = Snapshot.load(), snapshot.fuels == fuels {
                let stations = Array(StationSort.sorted(snapshot.stations, by: sort, fuels: fuels).prefix(Self.maxStations))
                WidgetStations.save(stations)
                return StationsEntry(date: .now, fuels: fuels, stations: stations, order: sort, state: .ready, updated: snapshot.date)
            }
            return StationsEntry(date: .now, fuels: fuels, stations: [], order: sort, state: .failed, updated: .now)
        }
    }

    /// The widget's own location when allowed (NSWidgetWantsLocation), else where the app last searched.
    private func currentLocation() async -> CLLocationCoordinate2D? {
        let fetcher = await WidgetLocationFetcher()
        if let coordinate = await fetcher.fetchCoordinate() {
            Preferences.shared.lastLocation = .init(
                latitude: (coordinate.latitude * 1000).rounded() / 1000,
                longitude: (coordinate.longitude * 1000).rounded() / 1000,
                date: .now
            )
            return coordinate
        }
        return Preferences.shared.lastLocation.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
