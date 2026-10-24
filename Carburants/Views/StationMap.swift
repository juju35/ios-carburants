import CarburantsKit
import MapKit
import SwiftUI

/// The stations as price tags on the map, as Plans shows fuel prices; the cheapest in green.
struct StationMap: View {
    @Bindable var model: StationsModel
    @Binding var camera: MapCameraPosition

    // More tags than that clutter the map; the list has them all.
    private static let maxMarkers = 30

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(Array(model.visible.prefix(Self.maxMarkers))) { station in
                Annotation(station.name, coordinate: station.coordinate, anchor: .bottom) {
                    PriceTag(
                        station: station,
                        fuels: model.fuels,
                        cheapest: model.isCheapest(station),
                        selected: model.selectedID == station.id
                    )
                    .onTapGesture { model.selectedID = station.id }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: true))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapPitchToggle()
            MapScaleView()
        }
    }
}

/// Logo and price in a bubble pointing at the station.
struct PriceTag: View {
    let station: Station
    let fuels: [Fuel]
    let cheapest: Bool
    let selected: Bool

    var body: some View {
        let fill: Color = cheapest ? .green : Color(.systemBackground)
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                StationLogo(station, size: 22)
                Text(priceText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(cheapest ? .white : .primary)
            }
            .padding(.leading, 3)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))

            Triangle()
                .fill(fill)
                .frame(width: 10, height: 6)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        .scaleEffect(selected ? 1.15 : 1, anchor: .bottom)
        .animation(.snappy, value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(station.name), \(priceText)")
        .accessibilityAddTraits(.isButton)
    }

    private var priceText: String {
        if let best = station.best(fuels) { return Format.priceNumber(best.price) }
        return station.sellsAny(fuels) ? "Rupture" : "–"
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
