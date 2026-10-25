import Foundation

/// "Prix des carburants en France – Flux instantané v2" (data.economie.gouv.fr), no key.
/// Same queries and parsing as ha-carburants-france's api.py and aaos-carburants.
public enum CarburantsAPI {
    private static let records =
        "https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/prix-des-carburants-en-france-flux-instantane-v2/records"
    private static let maxResults = 50

    /// Up to 50 stations around the point, nearest first, that sell one of `fuels` (or had a shortage of it).
    public static func nearby(latitude: Double, longitude: Double, radiusKm: Int, fuels: [Fuel]) async throws -> [Station] {
        let point = "geom'POINT(\(coordinate(longitude)) \(coordinate(latitude)))'"
        let area = "within_distance(geom, \(point), \(radiusKm)km)"
        let sold = "(" + fuels.map { "\($0.key)_prix is not null OR \($0.key)_rupture_type is not null" }
            .joined(separator: " OR ") + ")"
        let order = "distance(geom, \(point))"
        let data: Data
        do {
            data = try await fetch(where: "\(area) AND \(sold)", orderBy: order)
        } catch let error as HTTPError where error.code == 400 {
            // Fall back to the plain area query if the filter is ever refused.
            data = try await fetch(where: area, orderBy: order)
        }
        return try parseRecords(data).map { station in
            var station = station
            station.distanceKm = Geo.distanceKm(latitude, longitude, station.latitude, station.longitude)
            return station
        }
    }

    /// Three decimals, about 100 m: enough to find the stations around, and no more of the user's position than that.
    /// Distances are still worked out on the device from the exact position.
    private static func coordinate(_ value: Double) -> String { String(format: "%.3f", value) }

    private static func fetch(where filter: String, orderBy: String) async throws -> Data {
        try await HTTP.get(HTTP.url(records, ["where": filter, "order_by": orderBy, "limit": String(maxResults)]))
    }

    /// The stations of one API response.
    public static func parseRecords(_ data: Data) throws -> [Station] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [Any]
        else { throw URLError(.cannotParseResponse) }
        return objects(results).compactMap(parseStation)
    }

    /// One record. Prices come from the flat `{fuel}_prix` fields: a fuel with a price is available,
    /// one with a shortage is not, one with neither but an ended shortage is kept without a price.
    /// Anything else is not sold here.
    static func parseStation(_ record: [String: Any]) -> Station? {
        let id: Int64? = switch record["id"] {
        case let number as NSNumber: number.int64Value
        case let text as String: Int64(text)
        default: nil
        }
        guard let id else { return nil }

        let latitude: Double
        let longitude: Double
        if let geom = record["geom"] as? [String: Any], let lat = number(geom["lat"]), let lon = number(geom["lon"]) {
            latitude = lat
            longitude = lon
        } else if let lat = number(record["latitude"]), let lon = number(record["longitude"]) {
            // The raw feed stores degrees * 100000 as strings.
            latitude = lat / 100_000
            longitude = lon / 100_000
        } else {
            return nil
        }

        let ended = endedRuptures(record["rupture"])
        var fuels: [Fuel: FuelPrice] = [:]
        for fuel in Fuel.allCases {
            let price = number(record["\(fuel.key)_prix"])
            let rupture = string(record["\(fuel.key)_rupture_type"])
            if price == nil, rupture == nil, ended[fuel] == nil { continue }
            fuels[fuel] = FuelPrice(
                price: price.map { ($0 * 1000).rounded() / 1000 },
                updated: parseTime(string(record["\(fuel.key)_maj"])),
                available: price != nil && rupture == nil,
                rupture: rupture,
                ruptureSince: rupture != nil ? parseTime(string(record["\(fuel.key)_rupture_debut"])) : nil
            )
        }

        return Station(
            id: id,
            address: string(record["adresse"]) ?? "",
            postcode: string(record["cp"]) ?? "",
            city: string(record["ville"]) ?? "",
            latitude: latitude,
            longitude: longitude,
            highway: string(record["pop"]) == "A",
            automate24: string(record["horaires_automate_24_24"]) == "Oui",
            hours: parseHours(record["horaires"]),
            services: (record["services_service"] as? [Any])?.compactMap { string($0) } ?? [],
            fuels: fuels
        )
    }

    /// "horaires" is a JSON string; "horaire" is one range or a list, "@ferme" "1" means closed.
    private static func parseHours(_ raw: Any?) -> [DayHours] {
        guard let hours = jsonValue(raw) as? [String: Any] else { return [] }
        return objects(hours["jour"]).compactMap { day -> DayHours? in
            guard let number = string(day["@id"]).flatMap({ Int($0) }), (1...7).contains(number) else { return nil }
            let ranges = objects(day["horaire"]).compactMap { range -> TimeRange? in
                let open = (string(range["@ouverture"]) ?? "").replacingOccurrences(of: ".", with: ":")
                let close = (string(range["@fermeture"]) ?? "").replacingOccurrences(of: ".", with: ":")
                return open.isEmpty || close.isEmpty ? nil : TimeRange(open: open, close: close)
            }
            return DayHours(day: number, closed: string(day["@ferme"]) == "1", ranges: ranges)
        }.sorted { $0.day < $1.day }
    }

    /// Fuels listed in the raw "rupture" JSON with an end date (shortage just lifted).
    private static func endedRuptures(_ raw: Any?) -> [Fuel: Date] {
        var result: [Fuel: Date] = [:]
        for item in objects(jsonValue(raw)) {
            let name = string(item["@nom"]) ?? ""
            guard let fuel = Fuel.allCases.first(where: { $0.apiName.caseInsensitiveCompare(name) == .orderedSame }),
                  let end = parseTime(string(item["@fin"]))
            else { continue }
            result[fuel] = end
        }
        return result
    }

    // MARK: - Times

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Feed times: ISO with offset, or "2026-10-20 18:05:00" in UTC.
    static func parseTime(_ value: String?) -> Date? {
        guard let text = value?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        return iso.date(from: text) ?? isoFractional.date(from: text)
            ?? plain.date(from: text.replacingOccurrences(of: "T", with: " "))
    }

    // MARK: - JSON

    private static func jsonValue(_ raw: Any?) -> Any? {
        guard let text = raw as? String else { return raw }
        return try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
    }

    private static func objects(_ value: Any?) -> [[String: Any]] {
        switch value {
        case let object as [String: Any]: [object]
        case let array as [Any]: array.compactMap { $0 as? [String: Any] }
        default: []
        }
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let text as String: Double(text.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }
}
