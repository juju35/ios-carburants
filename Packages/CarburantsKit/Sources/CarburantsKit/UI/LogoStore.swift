import CryptoKit
import Foundation
import Observation
import UIKit

/// Station logos: shipped with the app (42 French networks), else downloaded from Wikimedia Commons and
/// kept in the App Group (the widget reads them from there), else the brand's initials.
@Observable
public final class LogoStore: @unchecked Sendable {
    public static let shared = LogoStore()

    public enum Artwork {
        /// `dark`: a white logo, drawn on a dark tile.
        case logo(UIImage, dark: Bool)
        case initials(String)
        case generic
    }

    /// Bumped when downloaded logos arrive, so views showing initials redraw.
    public private(set) var revision = 0

    private let shipped = ShippedLogos()
    private let memory = NSCache<NSURL, UIImage>()
    private let directory: URL = {
        let dir = SharedStorage.directory.appendingPathComponent("logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    public func artwork(for station: Station) -> Artwork {
        if let logo = shipped.find(station.brand, station.name) { return .logo(logo.image, dark: logo.dark) }
        if let url = station.logoURL, let image = cached(url) { return .logo(image, dark: false) }
        if let brand = station.brand { return .initials(Self.initials(brand)) }
        // Initials of an address mean nothing.
        return .generic
    }

    /// Downloads the logos not on disk yet. True when one is new.
    @discardableResult
    public func preload(_ stations: [Station]) async -> Bool {
        let urls = Set(stations.compactMap { shipped.find($0.brand, $0.name) == nil ? $0.logoURL : nil })
        var any = false
        for url in urls where cached(url) == nil {
            guard let data = try? await HTTP.get(url), let image = UIImage(data: data) else { continue }
            try? data.write(to: file(url), options: .atomic)
            memory.setObject(image, forKey: url as NSURL)
            any = true
        }
        if any { await MainActor.run { revision += 1 } }
        return any
    }

    private func cached(_ url: URL) -> UIImage? {
        if let image = memory.object(forKey: url as NSURL) { return image }
        guard let image = UIImage(contentsOfFile: file(url).path) else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }

    private func file(_ url: URL) -> URL {
        let hash = Insecure.SHA1.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".img")
    }

    static func initials(_ text: String) -> String {
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let letters = words.prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// Brand logos shipped in the package (Resources/brand_logos.json + Resources/Logos), found from the brand
/// or station name. A key matches the whole name, or its start when 4 letters or more; the longest wins.
final class ShippedLogos: @unchecked Sendable {
    struct Logo {
        let image: UIImage
        let dark: Bool
    }

    private struct Entry {
        let key: String
        let file: String
        let dark: Bool
    }

    private struct Manifest: Decodable {
        struct Brand: Decodable {
            let keys: [String]
            let logo: String
            let dark: Bool?
        }

        let brands: [Brand]
    }

    private static let minPrefix = 4

    // Longest keys first: "totalaccess" before "total", "geantcasino" before "casino".
    private lazy var entries: [Entry] = {
        guard let url = Bundle.module.url(forResource: "brand_logos", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return [] }
        return manifest.brands.flatMap { brand in
            brand.keys.map { Entry(key: $0, file: brand.logo, dark: brand.dark ?? false) }
        }.sorted { $0.key.count > $1.key.count }
    }()

    private let images = NSCache<NSString, UIImage>()
    private let lock = NSLock()

    /// The logo for these names (brand first, then station name), nil when none is shipped.
    func find(_ names: String?...) -> Logo? {
        for name in names.compactMap({ $0 }) {
            if let logo = match(name) { return logo }
        }
        return nil
    }

    private func match(_ name: String) -> Logo? {
        let key = TextCase.key(name)
        guard !key.isEmpty else { return nil }
        lock.lock()
        let entry = entries.first { key == $0.key || ($0.key.count >= Self.minPrefix && key.hasPrefix($0.key)) }
        lock.unlock()
        guard let entry, let image = image(entry.file) else { return nil }
        return Logo(image: image, dark: entry.dark)
    }

    private func image(_ file: String) -> UIImage? {
        if let image = images.object(forKey: file as NSString) { return image }
        guard let url = Bundle.module.url(forResource: file, withExtension: "png", subdirectory: "Logos"),
              let image = UIImage(contentsOfFile: url.path)
        else { return nil }
        images.setObject(image, forKey: file as NSString)
        return image
    }
}
