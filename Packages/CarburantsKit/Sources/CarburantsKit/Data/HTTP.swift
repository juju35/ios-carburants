import Foundation

public struct HTTPError: LocalizedError, Sendable {
    public let code: Int
    public var errorDescription: String? { "HTTP \(code)" }
}

enum HTTP {
    // Wikimedia and Overpass ask for an identifying User-Agent.
    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Carburants-iOS/\(version) (+https://github.com/juju35/ios-carburants)"
    }()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    static func query(_ params: KeyValuePairs<String, String>) -> String {
        params.map { "\(encode($0.key))=\(encode($0.value))" }.joined(separator: "&")
    }

    static func url(_ base: String, _ params: KeyValuePairs<String, String>) -> URL {
        URL(string: base + "?" + query(params))!
    }

    static func get(_ url: URL, timeout: TimeInterval = 15) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        return try await send(request)
    }

    static func postForm(_ url: URL, _ form: KeyValuePairs<String, String>, timeout: TimeInterval = 40) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(query(form).utf8)
        return try await send(request)
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw HTTPError(code: code) }
        return data
    }
}

/// Where caches and choices live: the App Group, shared by the app, CarPlay and the widget.
public enum SharedStorage {
    public static let appGroup = "group.me.jstephan.carburants"

    public static let directory: URL = {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Library/Caches", isDirectory: true)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Carburants", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    public static func file(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static func readJSON<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: file(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func writeJSON<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: file(name), options: .atomic)
    }
}

/// A file downloaded at most once per `maxAge` and kept on disk: an outage only means the cached copy.
struct CachedDownload {
    let name: String
    let url: URL
    let maxAge: TimeInterval

    /// `parse` may throw; a download parsed as empty is not kept.
    func load<T>(parse: (Data) throws -> T, isEmpty: (T) -> Bool) async -> T? {
        let file = SharedStorage.file(name)
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date
        if modified.map({ Date().timeIntervalSince($0) > maxAge }) ?? true {
            if let data = try? await HTTP.get(url, timeout: 30), let parsed = try? parse(data), !isEmpty(parsed) {
                try? data.write(to: file, options: .atomic)
                return parsed
            }
        }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? parse(data)
    }
}
