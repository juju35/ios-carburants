import Foundation

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

    /// Where the last search was made: the widget falls back on it when it has no location of its own.
    public var lastLocation: SavedLocation? {
        get { store.data(forKey: "lastLocation").flatMap { try? JSONDecoder().decode(SavedLocation.self, from: $0) } }
        set { store.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "lastLocation") }
    }
}

/// The stations the widgets show last, for their links into the app.
public enum WidgetStations {
    public static func load() -> [Station] { SharedStorage.readJSON([Station].self, from: "widget_stations.json") ?? [] }

    public static func save(_ stations: [Station]) { SharedStorage.writeJSON(stations, to: "widget_stations.json") }
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
