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
                    .onTapGesture {
                        withAnimation(.snappy) { model.selectedID = station.id }
                    }
                }
                .annotationTitles(.hidden)
            }
        }
        // Plans' default look: buildings and terrain in relief, traffic, no other places competing with the prices.
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: true))
        .sensoryFeedback(.selection, trigger: model.selectedID)
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
                StationLogo(station, size: selected ? 28 : 22)
                Text(priceText)
                    .font((selected ? Font.body : .subheadline).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(cheapest ? .white : .primary)
            }
            .padding(.leading, 3)
            .padding(.trailing, selected ? 10 : 8)
            .padding(.vertical, 3)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.blue : Color.primary.opacity(0.08), lineWidth: selected ? 2.5 : 0.5))

            Triangle()
                .fill(fill)
                .frame(width: 10, height: 6)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(selected ? 0.3 : 0.2), radius: selected ? 8 : 3, y: selected ? 4 : 1)
        .animation(.snappy, value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(station.name), \(priceText)")
        .accessibilityAddTraits(.isButton)
    }

    private var priceText: String {
        if let best = station.best(fuels) { return Format.priceNumber(best.price) }
        return station.inShortage(fuels) ? "Rupture" : "–"
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
