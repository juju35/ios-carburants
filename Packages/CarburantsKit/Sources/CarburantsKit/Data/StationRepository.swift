import Foundation

/// Stations around a point with their name, brand and logo URL. One per process, shared by the app,
/// CarPlay and the widget (whose caches live in the App Group).
public actor StationRepository {
    public static let shared = StationRepository()

    public static let radiusKm = 10
    public static let wideRadiusKm = 30
    private static let minResults = 3
    // The list must not wait long for the names file: names that come later are added by enrich().
    private static let namesWait: Duration = .milliseconds(2500)
    // Missing brand or logo: looked up again after a week.
    private static let retryInterval: TimeInterval = 7 * 24 * 3600
    private static let genericNames: Set<String> = [
        "station", "station service", "stationservice", "carburant", "carburants", "essence", "fuel",
    ]

    public struct SearchResult: Sendable {
        public let stations: [Station]
        public let radiusKm: Int
    }

    private struct BrandInfo: Codable {
        var brand: String?
        var osmName: String?
        var wikidata: String?
        var checkedAt: Date
    }

    private struct LogoInfo: Codable {
        var url: URL?
        var checkedAt: Date
    }

    private var names: [String: StationNames.Entry]?
    private var namesLoading = false
    private var brandIndex: [String: String] = [:]
    private var brands: [Int64: BrandInfo] = [:]
    private var logos: [String: LogoInfo] = [:]
    private var cachesLoaded = false

    private init() {}

    /// Starts the downloads (names ~1 MB, brand index) so the first search does not wait for them. App only:
    /// the widget extension's memory is too tight for them.
    public func warmUp() {
        loadCaches()
        startNamesLoad()
        if brandIndex.isEmpty {
            Task { brandIndex = await BrandIndex.load() }
        }
    }

    /// Nearest stations selling one of `fuels`, within 10 km, widened to 30 km when there are few.
    /// `withNamesFile: false` names them from the cached OpenStreetMap brands only (widget).
    public func nearby(latitude: Double, longitude: Double, fuels: [Fuel], withNamesFile: Bool = true) async throws -> SearchResult {
        var radius = Self.radiusKm
        var list = try await CarburantsAPI.nearby(latitude: latitude, longitude: longitude, radiusKm: radius, fuels: fuels)
        if list.filter({ $0.sellsAny(fuels) }).count < Self.minResults {
            radius = Self.wideRadiusKm
            list = try await CarburantsAPI.nearby(latitude: latitude, longitude: longitude, radiusKm: radius, fuels: fuels)
        }
        var names: [String: StationNames.Entry] = [:]
        if withNamesFile { names = await currentNames() }
        loadCaches()
        return SearchResult(stations: list.filter { $0.sellsAny(fuels) }.map { decorate($0, names) }, radiusKm: radius)
    }

    /// Names, brands and logo URLs of these stations (those shown): the names file if it came after the
    /// list, OpenStreetMap per station, then the logo of each brand. The changed stations by id, nil when none.
    public func enrich(_ stations: [Station]) async -> [Int64: Station]? {
        await lookupBrands(stations)
        let names = await currentNames()
        await lookupLogos(Set(stations.map { decorate($0, names) }.compactMap { qid($0) }))
        var changed: [Int64: Station] = [:]
        for station in stations {
            let decorated = decorate(station, names)
            if decorated != station { changed[station.id] = decorated }
        }
        return changed.isEmpty ? nil : changed
    }

    // MARK: - Names

    private func startNamesLoad() {
        guard names == nil, !namesLoading else { return }
        namesLoading = true
        Task {
            let loaded = await StationNames.load()
            names = loaded
            namesLoading = false
        }
    }

    private func currentNames() async -> [String: StationNames.Entry] {
        if let names, !names.isEmpty { return names }
        if names != nil {
            // Offline at start: try again for the next search.
            names = nil
            startNamesLoad()
            return [:]
        }
        startNamesLoad()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.namesWait)
        while names == nil, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return names ?? [:]
    }

    // MARK: - Brands and logos

    private func lookupBrands(_ stations: [Station]) async {
        let now = Date()
        let todo = stations.filter { station in
            guard let info = brands[station.id] else { return true }
            return (info.brand == nil || info.wikidata == nil) && now.timeIntervalSince(info.checkedAt) > Self.retryInterval
        }
        guard !todo.isEmpty, let found = try? await Overpass.lookup(todo) else { return }
        for station in todo {
            let tags = found[station.id]
            brands[station.id] = BrandInfo(brand: tags?.brand, osmName: tags?.name, wikidata: tags?.wikidata, checkedAt: now)
        }
        SharedStorage.writeJSON(brands, to: "brands.json")
    }

    private func lookupLogos(_ qids: Set<String>) async {
        let now = Date()
        let todo = qids.filter { qid in
            guard let info = logos[qid] else { return true }
            return info.url == nil && now.timeIntervalSince(info.checkedAt) > Self.retryInterval
        }
        guard !todo.isEmpty, let found = try? await WikidataLogos.urls(Set(todo)) else { return }
        for qid in todo {
            logos[qid] = LogoInfo(url: found[qid] ?? nil, checkedAt: now)
        }
        SharedStorage.writeJSON(logos, to: "logos.json")
    }

    private func loadCaches() {
        guard !cachesLoaded else { return }
        cachesLoaded = true
        brands = SharedStorage.readJSON([Int64: BrandInfo].self, from: "brands.json") ?? [:]
        logos = SharedStorage.readJSON([String: LogoInfo].self, from: "logos.json") ?? [:]
    }

    /// The brand's Wikidata id: from the OSM station, else from the brand name (name-suggestion-index).
    private func qid(_ station: Station) -> String? {
        let info = brands[station.id]
        return info?.wikidata
            ?? BrandIndex.qid(station.brand, in: brandIndex)
            ?? BrandIndex.qid(info?.brand, in: brandIndex)
    }

    /// Name shown: community file, OpenStreetMap, then brand + town, then address (station_title).
    private func decorate(_ station: Station, _ names: [String: StationNames.Entry]) -> Station {
        let community = names[String(station.id)]
        let info = brands[station.id]
        let brand = community?.brand.nonEmpty ?? info?.brand
        let city = station.prettyCity
        let title = community?.name.nonEmpty
            ?? Self.usefulOsmName(info?.osmName, brand: info?.brand)
            ?? brand.map { "\($0) \(city)".trimmingCharacters(in: .whitespaces) }
            ?? "\(station.prettyAddress.nonEmpty ?? "Station") \(city)".trimmingCharacters(in: .whitespaces)
        var decorated = station
        decorated.name = title
        decorated.brand = brand
        if let qid = qid(decorated), let url = logos[qid]?.url {
            decorated.logoURL = url
        }
        return decorated
    }

    private static func compact(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
            .replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// The OSM name, unless it says "Station-service" or is just the brand (short or long form).
    static func usefulOsmName(_ name: String?, brand: String?) -> String? {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let key = compact(name.replacingOccurrences(of: "-", with: " "))
        if genericNames.contains(key) { return nil }
        if let brand, !brand.trimmingCharacters(in: .whitespaces).isEmpty {
            let nameCompact = key.replacingOccurrences(of: " ", with: "")
            let brandCompact = compact(brand.replacingOccurrences(of: "-", with: " ")).replacingOccurrences(of: " ", with: "")
            // Shorter than the brand, or the brand plus a few letters ("Energies", an initial).
            let shortForm = brandCompact.contains(nameCompact)
            let longForm = nameCompact.contains(brandCompact) && nameCompact.count - brandCompact.count <= 8
            if !nameCompact.isEmpty, !brandCompact.isEmpty, shortForm || longForm { return nil }
        }
        return name.trimmingCharacters(in: .whitespaces)
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
