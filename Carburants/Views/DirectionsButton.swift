import CarburantsKit
import MapKit
import SwiftUI

/// "Itinéraire" button; opens user's preferred navigation app on click (Plans, Google Maps, Waze),
/// with long-press menu to choose an alternative app or set default.
struct DirectionsButton: View {
    let station: Station
    @Environment(\.openURL) private var openURL
    @State private var travelTime: TimeInterval?
    @State private var defaultApp = Preferences.shared.navigationApp

    var body: some View {
        Menu {
            ForEach(NavigationApp.allCases) { app in
                Button { open(app.url(for: station)) } label: {
                    Label(app.title, systemImage: app.symbol)
                }
            }

            Divider()

            Section("Application par défaut") {
                ForEach(NavigationApp.allCases) { app in
                    Button {
                        defaultApp = app
                        Preferences.shared.navigationApp = app
                    } label: {
                        if defaultApp == app {
                            Label(app.title, systemImage: "checkmark")
                        } else {
                            Text(app.title)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Image(systemName: "car.fill")
                    .font(.title3)
                VStack(alignment: .center, spacing: 2) {
                    Text("Itinéraire")
                        .font(.headline)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                    }
                }
                .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 6)
        } primaryAction: {
            open(defaultApp.url(for: station))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .controlSize(.large)
        .task(id: station.id) {
            defaultApp = Preferences.shared.navigationApp
            travelTime = nil
            await loadTravelTime()
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let travelTime {
            parts.append(Format.duration(travelTime))
        }
        if let distance = station.distanceKm {
            parts.append(Format.distance(distance))
        }
        return parts.joined(separator: " · ")
    }

    private func loadTravelTime() async {
        if let demo = Directions.demoTravelTime(for: station) {
            travelTime = demo
            return
        }
        let request = MKDirections.Request()
        request.source = .forCurrentLocation()
        request.destination = Directions.mapItem(for: station)
        request.transportType = .automobile
        let directions = MKDirections(request: request)
        if let response = try? await directions.calculateETA() {
            withAnimation(.snappy) {
                travelTime = response.expectedTravelTime
            }
        }
    }

    private func open(_ url: URL) {
        let fallback = NavigationApp.appleMaps.url(for: station)
        openURL(url) { accepted in
            if !accepted { openURL(fallback) }
        }
    }
}

enum Directions {
    /// Demo mode (screenshots): no route from the current location, which would ask for it; a travel time from the
    /// distance at 40 km/h instead.
    static func demoTravelTime(for station: Station) -> TimeInterval? {
        guard Demo.isOn else { return nil }
        return max(60, (station.distanceKm ?? 1) / 40 * 3600)
    }

    static func mapItem(for station: Station) -> MKMapItem {
        let coordinate = CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)
        if #available(iOS 26.0, *) {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let item = MKMapItem(location: location, address: nil)
            item.name = station.name
            return item
        } else {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            item.name = station.name
            return item
        }
    }
}
