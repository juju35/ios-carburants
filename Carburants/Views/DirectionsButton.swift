import CarburantsKit
import SwiftUI

/// "Itinéraire" in Plans; a long press offers Google Maps and Waze (Plans when they are not installed:
/// canOpenURL is deprecated since iOS 27, so the app tries and falls back).
struct DirectionsButton: View {
    let station: Station
    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            ForEach(Directions.apps(station), id: \.name) { app in
                Button { open(app.url) } label: { Label(app.name, systemImage: app.symbol) }
            }
        } label: {
            Label {
                VStack(spacing: 0) {
                    Text("Itinéraire").font(.headline)
                    if let distance = station.distanceKm {
                        Text(Format.distance(distance)).font(.caption)
                    }
                }
            } icon: {
                Image(systemName: "car.fill")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        } primaryAction: {
            openURL(Directions.appleMaps(station))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .controlSize(.large)
    }

    private func open(_ url: URL) {
        let fallback = Directions.appleMaps(station)
        openURL(url) { accepted in
            if !accepted { openURL(fallback) }
        }
    }
}

enum Directions {
    struct App {
        let name: String
        let symbol: String
        let url: URL
    }

    /// Driving directions in Plans (also what CarPlay opens).
    static func appleMaps(_ station: Station) -> URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: "\(station.latitude),\(station.longitude)"),
            URLQueryItem(name: "q", value: station.name),
            URLQueryItem(name: "dirflg", value: "d"),
        ]
        return components.url!
    }

    static func apps(_ station: Station) -> [App] {
        let lat = station.latitude
        let lon = station.longitude
        return [
            App(name: "Plans", symbol: "map", url: appleMaps(station)),
            App(name: "Google Maps", symbol: "arrow.triangle.turn.up.right.diamond",
                url: URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving")!),
            App(name: "Waze", symbol: "arrow.triangle.turn.up.right.diamond",
                url: URL(string: "waze://?ll=\(lat),\(lon)&navigate=yes")!),
        ]
    }
}
