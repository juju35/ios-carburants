import AppIntents
import CarburantsKit
import CoreLocation
import WidgetKit

/// The fuel a widget shows: those chosen in the app, or one in particular.
enum WidgetFuel: String, AppEnum {
    case mine, gazole, sp95, sp98, e10, e85, gplc

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Carburant"
    static let caseDisplayRepresentations: [WidgetFuel: DisplayRepresentation] = [
        .mine: "Mes carburants",
        .gazole: "Gazole",
        .sp95: "SP95",
        .sp98: "SP98",
        .e10: "SP95-E10",
        .e85: "E85",
        .gplc: "GPLc",
    ]

    var fuels: [Fuel] {
        Fuel(rawValue: rawValue).map { [$0] } ?? Preferences.shared.fuels
    }
}

struct StationsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Stations à proximité"
    // swiftlint:disable:next unused_declaration - shown by the system in the widget's settings
    static let description = IntentDescription("Les stations les moins chères autour de vous.")

    @Parameter(title: "Carburant", default: .mine)
    var fuel: WidgetFuel
}

struct StationsEntry: TimelineEntry {
    enum State {
        case ready, noLocation, failed
    }

    let date: Date
    let fuels: [Fuel]
    /// Cheapest first.
    let stations: [Station]
    let state: State
    /// When the prices were fetched (an older list is shown when offline).
    let updated: Date

    static let sample = StationsEntry(
        date: .now, fuels: [.gazole],
        stations: StationSort.sorted(Station.samples, by: .price, fuels: [.gazole]),
        state: .ready, updated: .now
    )
}

struct StationsProvider: AppIntentTimelineProvider {
    // Prices change every 10 minutes at most; WidgetKit spaces reloads out anyway.
    private static let refresh: TimeInterval = 30 * 60
    private static let maxStations = 8

    func placeholder(in context: Context) -> StationsEntry { .sample }

    func snapshot(for configuration: StationsIntent, in context: Context) async -> StationsEntry {
        if context.isPreview { return .sample }
        return await load(configuration.fuel.fuels)
    }

    func timeline(for configuration: StationsIntent, in context: Context) async -> Timeline<StationsEntry> {
        let entry = await load(configuration.fuel.fuels)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(Self.refresh)))
    }

    private func load(_ fuels: [Fuel]) async -> StationsEntry {
        guard let location = currentLocation() else {
            return StationsEntry(date: .now, fuels: fuels, stations: [], state: .noLocation, updated: .now)
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
            let stations = Array(StationSort.sorted(named, by: .price, fuels: fuels).prefix(Self.maxStations))
            await LogoStore.shared.preload(stations)
            WidgetStations.save(stations)
            return StationsEntry(date: .now, fuels: fuels, stations: stations, state: .ready, updated: .now)
        } catch {
            // Offline: the app's last list when it was for these fuels.
            if let snapshot = Snapshot.load(), snapshot.fuels == fuels {
                let stations = Array(StationSort.sorted(snapshot.stations, by: .price, fuels: fuels).prefix(Self.maxStations))
                return StationsEntry(date: .now, fuels: fuels, stations: stations, state: .ready, updated: snapshot.date)
            }
            return StationsEntry(date: .now, fuels: fuels, stations: [], state: .failed, updated: .now)
        }
    }

    /// The widget's own location when allowed (NSWidgetWantsLocation), else where the app last searched.
    private func currentLocation() -> CLLocationCoordinate2D? {
        let manager = CLLocationManager()
        if manager.isAuthorizedForWidgetUpdates, let location = manager.location,
           Date().timeIntervalSince(location.timestamp) < 2 * 3600 {
            return location.coordinate
        }
        return Preferences.shared.lastLocation.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
