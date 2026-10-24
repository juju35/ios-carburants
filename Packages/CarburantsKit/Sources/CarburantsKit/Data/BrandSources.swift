import Foundation

/// Station names from Aohzan/hass-prixcarburant's community file (stations_name.json, `{id: {name, brand}}`,
/// Apache-2.0), as in ha-carburants-france's names.py. Downloaded at most once a week.
enum StationNames {
    struct Entry: Sendable {
        let name: String
        let brand: String
    }

    private static let download = CachedDownload(
        name: "stations_name.json",
        url: URL(string: "https://raw.githubusercontent.com/Aohzan/hass-prixcarburant/refs/heads/master/custom_components/prix_carburant/stations_name.json")!,
        maxAge: 7 * 24 * 3600
    )

    static func load() async -> [String: Entry] {
        await download.load(parse: parse, isEmpty: \.isEmpty) ?? [:]
    }

    static func parse(_ data: Data) throws -> [String: Entry] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var names: [String: Entry] = [:]
        names.reserveCapacity(json.count)
        for (id, value) in json {
            guard let info = value as? [String: Any] else { continue }
            let name = (info["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let brand = (info["brand"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            if !name.isEmpty || !brand.isEmpty { names[id] = Entry(name: TextCase.name(name), brand: brand) }
        }
        return names
    }
}

/// Brand name -> Wikidata id for fuel stations, from OpenStreetMap's name-suggestion-index
/// (data/brands/amenity/fuel.json, BSD-3-Clause). Used when the OSM station has no `brand:wikidata`
/// but its brand is known. Downloaded at most once a week.
enum BrandIndex {
    private static let download = CachedDownload(
        name: "nsi_fuel.json",
        url: URL(string: "https://raw.githubusercontent.com/osmlab/name-suggestion-index/main/data/brands/amenity/fuel.json")!,
        maxAge: 7 * 24 * 3600
    )

    static func load() async -> [String: String] {
        await download.load(parse: parse, isEmpty: \.isEmpty) ?? [:]
    }

    /// "Intermarché Super Rennes" falls back to "Intermarché Super", then "Intermarché".
    static func qid(_ brand: String?, in index: [String: String]) -> String? {
        var words = (brand ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        while !words.isEmpty {
            if let qid = index[TextCase.key(words.joined(separator: " "))] { return qid }
            words.removeLast()
        }
        return nil
    }

    /// Brands used in France (or worldwide / Europe) first: a French brand wins a name clash.
    static func parse(_ data: Data) throws -> [String: String] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else { return [:] }
        var map: [String: String] = [:]
        for item in items.sorted(by: { rank($0) < rank($1) }) {
            if rank(item) > 2 { break } // Not used in France.
            guard let tags = item["tags"] as? [String: Any],
                  let qid = tags["brand:wikidata"] as? String, qid.hasPrefix("Q")
            else { continue }
            let names = [item["displayName"], tags["brand"], tags["name"]].compactMap { $0 as? String }
                + ((item["matchNames"] as? [Any])?.compactMap { $0 as? String } ?? [])
            for name in names {
                let key = TextCase.key(name)
                if !key.isEmpty, map[key] == nil { map[key] = qid }
            }
        }
        return map
    }

    /// 0: France listed, 1: Europe, 2: world, 3: elsewhere only or France excluded.
    private static func rank(_ item: [String: Any]) -> Int {
        guard let set = item["locationSet"] as? [String: Any] else { return 2 }
        let include = (set["include"] as? [Any] ?? []).compactMap { ($0 as? String)?.lowercased() }
        let exclude = (set["exclude"] as? [Any] ?? []).compactMap { ($0 as? String)?.lowercased() }
        if exclude.contains("fr") { return 3 }
        if include.contains(where: { $0 == "fr" || $0.hasPrefix("fr-") || $0.hasPrefix("fr.") }) { return 0 }
        if include.contains("150") { return 1 }
        if include.contains("001") || include.isEmpty { return 2 }
        return 3
    }
}

/// Brand and name of stations from OpenStreetMap (Overpass): the station carrying the feed id in
/// `ref:FR:prix-carburants`, else the nearest branded one.
enum Overpass {
    struct Tags: Codable, Sendable {
        let brand: String?
        let name: String?
        let wikidata: String?
    }

    private static let url = URL(string: "https://overpass-api.de/api/interpreter")!
    // The feed's coordinates are rounded to ~100 m and sometimes sit on the street.
    private static let nearbyMeters = 300

    static func lookup(_ stations: [Station]) async throws -> [Int64: Tags] {
        let parts = stations.map {
            "nwr[\"amenity\"=\"fuel\"](around:\(nearbyMeters),\($0.latitude),\($0.longitude));"
        }.joined()
        let data = try await HTTP.postForm(url, ["data": "[out:json][timeout:30];(\(parts));out tags center;"])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let elements = (json?["elements"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        var found: [Int64: Tags] = [:]
        for station in stations {
            if let tags = match(station, elements) { found[station.id] = tags }
        }
        return found
    }

    private static func match(_ station: Station, _ elements: [[String: Any]]) -> Tags? {
        let sid = String(station.id)
        var nearest: [String: Any]?
        var best = Double.greatestFiniteMagnitude
        for element in elements {
            guard let tags = element["tags"] as? [String: Any] else { continue }
            let refs = (tags["ref:FR:prix-carburants"] as? String ?? "").replacingOccurrences(of: " ", with: "")
                .split(separator: ";").map(String.init)
            if refs.contains(sid) { return makeTags(tags) }
            if let distance = distanceIfBranded(station, element, tags), distance < best {
                best = distance
                nearest = tags
            }
        }
        return nearest.map(makeTags)
    }

    private static func distanceIfBranded(_ station: Station, _ element: [String: Any], _ tags: [String: Any]) -> Double? {
        if (tags["brand"] as? String ?? "").isEmpty, (tags["name"] as? String ?? "").isEmpty { return nil }
        let point = element["lat"] != nil ? element : element["center"] as? [String: Any]
        guard let lat = (point?["lat"] as? NSNumber)?.doubleValue, let lon = (point?["lon"] as? NSNumber)?.doubleValue else {
            return nil
        }
        return Geo.distanceKm(station.latitude, station.longitude, lat, lon)
    }

    private static func makeTags(_ tags: [String: Any]) -> Tags {
        func value(_ key: String) -> String? {
            guard let text = tags[key] as? String, !text.isEmpty else { return nil }
            return text
        }
        let name = value("name")
        return Tags(brand: value("brand") ?? name, name: name, wikidata: value("brand:wikidata"))
    }
}

/// Brand logos from Wikidata, served by Wikimedia Commons.
enum WikidataLogos {
    private static let api = "https://www.wikidata.org/w/api.php"
    private static let commons = "https://commons.wikimedia.org/wiki/Special:FilePath/"
    // Small logo or icon (square), then logo image.
    private static let logoProperties = ["P8972", "P154"]
    // Parent organisation, then part of: where a sub-brand's logo is found.
    private static let parentProperties = ["P749", "P361"]

    /// Logo URL per brand. Sub-brands (Super U, Carrefour Market…) often have no logo of their own:
    /// they take their parent organisation's, else what they are part of.
    static func urls(_ qids: Set<String>) async throws -> [String: URL?] {
        let claims = try await entityClaims(qids)
        var files: [String: String?] = [:]
        for qid in qids { files[qid] = claims[qid].flatMap(logoFile) }
        var parents: [String: String] = [:]
        for (qid, file) in files where file == nil {
            if let parent = claims[qid].flatMap(parentOf) { parents[qid] = parent }
        }
        if !parents.isEmpty {
            let parentClaims = try await entityClaims(Set(parents.values))
            for (qid, parent) in parents { files[qid] = parentClaims[parent].flatMap(logoFile) }
        }
        return files.mapValues { file in
            file.flatMap { URL(string: commons + HTTP.encode($0.replacingOccurrences(of: " ", with: "_")) + "?width=128") }
        }
    }

    private static func entityClaims(_ qids: Set<String>) async throws -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        let sorted = qids.filter { $0.hasPrefix("Q") }.sorted()
        for start in stride(from: 0, to: sorted.count, by: 50) {
            let chunk = Array(sorted[start..<min(start + 50, sorted.count)])
            let url = HTTP.url(api, [
                "action": "wbgetentities", "ids": chunk.joined(separator: "|"), "props": "claims", "format": "json",
            ])
            let data = try await HTTP.get(url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let entities = json?["entities"] as? [String: Any] else { continue }
            for qid in chunk {
                if let claims = (entities[qid] as? [String: Any])?["claims"] as? [String: Any] { result[qid] = claims }
            }
        }
        return result
    }

    private static func logoFile(_ claims: [String: Any]) -> String? {
        for property in logoProperties {
            if let file = current(claims[property], accepts: { $0 is String }) as? String { return file }
        }
        return nil
    }

    private static func parentOf(_ claims: [String: Any]) -> String? {
        for property in parentProperties {
            let value = current(claims[property], accepts: { $0 is [String: Any] }) as? [String: Any]
            if let id = value?["id"] as? String, id.hasPrefix("Q") { return id }
        }
        return nil
    }

    /// Value of the current statement: brands keep their old logos with an end time, so the preferred
    /// rank first, else one with no end time (P582), else the last one.
    private static func current(_ raw: Any?, accepts: (Any?) -> Bool) -> Any? {
        let usable = (raw as? [Any] ?? []).compactMap { $0 as? [String: Any] }.filter {
            ($0["rank"] as? String) != "deprecated" && accepts(value($0))
        }
        guard let last = usable.last else { return nil }
        let claim = usable.first(where: { ($0["rank"] as? String) == "preferred" })
            ?? usable.last(where: { (($0["qualifiers"] as? [String: Any])?["P582"]) == nil })
            ?? last
        return value(claim)
    }

    private static func value(_ claim: [String: Any]) -> Any? {
        ((claim["mainsnak"] as? [String: Any])?["datavalue"] as? [String: Any])?["value"]
    }
}
