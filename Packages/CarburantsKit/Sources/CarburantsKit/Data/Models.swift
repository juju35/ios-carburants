// swiftlint:disable:next unused_import - also reached through another import, kept explicit for Swift 6
import CoreLocation
import Foundation

/// Fuels of the government feed. `rawValue` prefixes the API fields (`{key}_prix`, `{key}_maj`…),
/// `apiName` is the name used in the raw "rupture" JSON. Colours and EU identifiers (EN 16942)
/// are the pump ones, as in the Lovelace card and the Android Automotive app.
public enum Fuel: String, CaseIterable, Codable, Hashable, Sendable, Identifiable, CodingKeyRepresentable {
    case gazole, sp95, sp98, e10, e85, gplc

    public var id: String { rawValue }
    public var key: String { rawValue }

    public var apiName: String {
        switch self {
        case .gazole: "Gazole"
        case .sp95: "SP95"
        case .sp98: "SP98"
        case .e10: "E10"
        case .e85: "E85"
        case .gplc: "GPLc"
        }
    }

    public var label: String {
        switch self {
        case .e10: "SP95-E10"
        default: apiName
        }
    }

    /// Name in a tight line: "E10" rather than "SP95-E10".
    public var short: String { self == .e10 ? "E10" : label }

    /// EU pump identifier, empty when there is none to show.
    public var euCode: String {
        switch self {
        case .gazole: "B7"
        case .sp95, .sp98: "E5"
        case .e10: "E10"
        case .e85, .gplc: ""
        }
    }

    public var summary: String {
        switch self {
        case .gazole: "Diesel"
        case .sp95: "Sans plomb 95"
        case .sp98: "Sans plomb 98"
        case .e10: "Sans plomb 95-E10"
        case .e85: "Superéthanol"
        case .gplc: "Gaz de pétrole liquéfié"
        }
    }

    /// Pump colour, 0xRRGGBB.
    public var rgb: UInt32 {
        switch self {
        case .gazole: 0xE8A000
        case .sp95: 0x00A651
        case .sp98: 0x00703C
        case .e10: 0x009A3E
        case .e85: 0x0057A8
        case .gplc: 0xC62828
        }
    }

    /// Dark text on the yellow diesel badge, white elsewhere.
    public var darkText: Bool { self == .gazole }
}

public let ruptureDefinitive = "definitive"

public struct FuelPrice: Codable, Hashable, Sendable {
    public var price: Double?
    public var updated: Date?
    public var available: Bool
    /// "temporaire" or "definitive", nil when in stock.
    public var rupture: String?
    public var ruptureSince: Date?

    public init(price: Double?, updated: Date?, available: Bool, rupture: String?, ruptureSince: Date?) {
        self.price = price
        self.updated = updated
        self.available = available
        self.rupture = rupture
        self.ruptureSince = ruptureSince
    }
}

public struct TimeRange: Codable, Hashable, Sendable {
    /// "HH:mm"
    public var open: String
    public var close: String

    public init(open: String, close: String) {
        self.open = open
        self.close = close
    }
}

/// Opening hours of one day, `day` 1 = Monday … 7 = Sunday.
public struct DayHours: Codable, Hashable, Sendable {
    public var day: Int
    public var closed: Bool
    public var ranges: [TimeRange]

    public init(day: Int, closed: Bool, ranges: [TimeRange]) {
        self.day = day
        self.closed = closed
        self.ranges = ranges
    }
}

public struct Station: Codable, Hashable, Identifiable, Sendable {
    public var id: Int64
    public var address: String
    public var postcode: String
    public var city: String
    public var latitude: Double
    public var longitude: Double
    public var highway: Bool
    public var automate24: Bool
    public var hours: [DayHours]
    public var services: [String]
    public var fuels: [Fuel: FuelPrice]
    public var distanceKm: Double?
    /// Display name, see `StationRepository.decorate`.
    public var name: String
    public var brand: String?
    public var logoURL: URL?

    public init(
        id: Int64, address: String, postcode: String, city: String, latitude: Double, longitude: Double,
        highway: Bool = false, automate24: Bool = false, hours: [DayHours] = [], services: [String] = [],
        fuels: [Fuel: FuelPrice], distanceKm: Double? = nil, name: String = "", brand: String? = nil,
        logoURL: URL? = nil
    ) {
        self.id = id
        self.address = address
        self.postcode = postcode
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
        self.highway = highway
        self.automate24 = automate24
        self.hours = hours
        self.services = services
        self.fuels = fuels
        self.distanceKm = distanceKm
        self.name = name
        self.brand = brand
        self.logoURL = logoURL
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Sold here, possibly in a temporary shortage.
    public func sells(_ fuel: Fuel) -> Bool {
        guard let price = fuels[fuel] else { return false }
        return price.rupture != ruptureDefinitive
    }

    public func sellsAny(_ list: [Fuel]) -> Bool { list.contains(where: sells) }

    /// Price when in stock.
    public func price(_ fuel: Fuel) -> Double? {
        guard let price = fuels[fuel], price.available else { return nil }
        return price.price
    }

    /// In a declared shortage of one of `list` (a fuel kept after its shortage ended has no price, but is no shortage).
    public func inShortage(_ list: [Fuel]) -> Bool {
        list.contains { sells($0) && fuels[$0]?.rupture != nil }
    }

    /// Cheapest in-stock price among `list`, with its fuel.
    public func best(_ list: [Fuel]) -> (fuel: Fuel, price: Double)? {
        list.compactMap { fuel in price(fuel).map { (fuel: fuel, price: $0) } }.min { $0.price < $1.price }
    }

    /// Headline fuel: the cheapest in stock among `list`, else the first one sold here.
    public func mainFuel(_ list: [Fuel]) -> Fuel? {
        best(list)?.fuel ?? list.first(where: sells)
    }

    public var prettyCity: String { TextCase.city(city) }
    public var prettyAddress: String { TextCase.address(address) }
}

public enum StationOrder: String, Codable, CaseIterable, Sendable {
    case price, distance

    public var label: String { self == .price ? "Prix" : "Distance" }
}

public enum StationSort {
    /// Cheapest of the chosen fuels first (shortages last, nearest first), or nearest first.
    public static func sorted(_ list: [Station], by order: StationOrder, fuels: [Fuel]) -> [Station] {
        let distance: (Station) -> Double = { $0.distanceKm ?? .greatestFiniteMagnitude }
        switch order {
        case .distance:
            return list.sorted { distance($0) < distance($1) }
        case .price:
            return list.sorted { lhs, rhs in
                let left = lhs.best(fuels)?.price ?? .greatestFiniteMagnitude
                let right = rhs.best(fuels)?.price ?? .greatestFiniteMagnitude
                return left == right ? distance(lhs) < distance(rhs) : left < right
            }
        }
    }
}

public enum Geo {
    /// Great-circle distance in km.
    public static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dp = p2 - p1
        let dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 6371 * 2 * asin(sqrt(a))
    }
}
