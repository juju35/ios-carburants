import CarburantsKit
import SwiftUI

/// "Itinéraire" in Plans; a long press offers Google Maps and Waze when they are installed.
struct DirectionsButton: View {
    let station: Station
    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            Button { openURL(Directions.appleMaps(station)) } label: { Label("Plans", systemImage: "map") }
            ForEach(Directions.otherApps(station), id: \.name) { app in
                Button { openURL(app.url) } label: { Label(app.name, systemImage: "arrow.triangle.turn.up.right.diamond") }
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
}

enum Directions {
    struct App {
        let name: String
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

    /// Navigation apps installed besides Plans (their schemes are listed in LSApplicationQueriesSchemes).
    @MainActor
    static func otherApps(_ station: Station) -> [App] {
        let lat = station.latitude
        let lon = station.longitude
        let apps = [
            App(name: "Google Maps", url: URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving")!),
            App(name: "Waze", url: URL(string: "waze://?ll=\(lat),\(lon)&navigate=yes")!),
        ]
        return apps.filter { UIApplication.shared.canOpenURL($0.url) }
    }
}
