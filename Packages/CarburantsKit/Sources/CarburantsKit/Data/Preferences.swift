import Foundation

/// Preferred app for driving directions.
public enum NavigationApp: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleMaps = "apple_maps"
    case googleMaps = "google_maps"
    case waze = "waze"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appleMaps: "Plans"
        case .googleMaps: "Google Maps"
        case .waze: "Waze"
        }
    }

    public var symbol: String {
        switch self {
        case .appleMaps: "map"
        case .googleMaps, .waze: "arrow.triangle.turn.up.right.diamond"
        }
    }

    public func url(for station: Station) -> URL {
        let fallback = URL(string: "https://maps.apple.com/?daddr=\(station.latitude),\(station.longitude)&dirflg=d")
            ?? URL(fileURLWithPath: "/")
        switch self {
        case .appleMaps:
            var components = URLComponents(string: "https://maps.apple.com/")
            components?.queryItems = [
                URLQueryItem(name: "daddr", value: "\(station.latitude),\(station.longitude)"),
                URLQueryItem(name: "q", value: station.name),
                URLQueryItem(name: "dirflg", value: "d"),
            ]
            return components?.url ?? fallback
        case .googleMaps:
            let lat = station.latitude
            let lon = station.longitude
            return URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving") ?? fallback
        case .waze:
            let lat = station.latitude
            let lon = station.longitude
            return URL(string: "waze://?ll=\(lat),\(lon)&navigate=yes") ?? fallback
        }
    }
}

/// Choices kept between drives, shared with the widget through the App Group.
public final class Preferences: @unchecked Sendable {
    public static let shared = Preferences()

    private let store = UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard

    public struct SavedLocation: Codable, Sendable {
        public let latitude: Double
        public let longitude: Double
        public let date: Date

        public init(latitude: Double, longitude: Double, date: Date) {
            self.latitude = latitude
            self.longitude = longitude
            self.date = date
        }
    }

    /// Fuels shown (those the car takes), in the declaration order, never empty.
    public var fuels: [Fuel] {
        get {
            let stored = Set(store.stringArray(forKey: "fuels") ?? [])
            let fuels = Fuel.allCases.filter { stored.contains($0.key) }
            return fuels.isEmpty ? [.gazole] : fuels
        }
        set { store.set(newValue.map(\.key), forKey: "fuels") }
    }

    public var sort: StationOrder {
        get { store.string(forKey: "sort").flatMap(StationOrder.init(rawValue:)) ?? .price }
        set { store.set(newValue.rawValue, forKey: "sort") }
    }

    public var navigationApp: NavigationApp {
        get { store.string(forKey: "navigationApp").flatMap(NavigationApp.init(rawValue:)) ?? .appleMaps }
        set { store.set(newValue.rawValue, forKey: "navigationApp") }
    }

    /// Where the last search was made: the widget falls back on it when it has no location of its own.
    public var lastLocation: SavedLocation? {
        get { store.data(forKey: "lastLocation").flatMap { try? JSONDecoder().decode(SavedLocation.self, from: $0) } }
        set { store.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "lastLocation") }
    }
}

/// The stations the widgets showed lately, for their links into the app. Each widget (one per fuel, say) adds its
/// own to the file instead of replacing the others'; the most recent ones are kept.
public enum WidgetStations {
    private static let file = "widget_stations.json"
    private static let limit = 100

    public static func load() -> [Station] { SharedStorage.readJSON([Station].self, from: file) ?? [] }

    public static func save(_ stations: [Station]) {
        let ids = Set(stations.map(\.id))
        let kept = load().filter { !ids.contains($0.id) }
        SharedStorage.writeJSON(Array((stations + kept).prefix(limit)), to: file)
    }
}

/// The last list found, so the app and the widget have something to show at once.
public struct Snapshot: Codable, Sendable {
    public let date: Date
    public let latitude: Double
    public let longitude: Double
    public let fuels: [Fuel]
    public let radiusKm: Int
    public let stations: [Station]

    public init(date: Date, latitude: Double, longitude: Double, fuels: [Fuel], radiusKm: Int, stations: [Station]) {
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
        self.fuels = fuels
        self.radiusKm = radiusKm
        self.stations = stations
    }

    public static func load() -> Snapshot? { SharedStorage.readJSON(Snapshot.self, from: "snapshot.json") }

    public func save() { SharedStorage.writeJSON(self, to: "snapshot.json") }
}
