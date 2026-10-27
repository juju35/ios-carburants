import CarburantsKit
import SwiftUI

/// Logo, name, distance and opening status; the price of the cheapest of your fuels on the right.
struct StationRow: View {
    let station: Station
    let fuels: [Fuel]
    let cheapest: Bool

    var body: some View {
        HStack(spacing: 12) {
            StationLogo(station, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(station.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let distance = station.distanceKm {
                        Text(Format.distance(distance))
                    }
                    if let opening = Opening.of(station) {
                        Text("·")
                        Text(opening.text).foregroundStyle(opening.state.color)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                if let best = station.best(fuels) {
                    PriceText(best.price)
                        .foregroundStyle(cheapest ? .green : .primary)
                    if fuels.count > 1 { FuelBadge(best.fuel) }
                } else if station.inShortage(fuels) {
                    Text("Rupture")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                } else {
                    Text("Prix indisponible")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    List(Station.samples) { StationRow(station: $0, fuels: [.gazole, .e10], cheapest: $0.id == 35000001) }
        .listStyle(.plain)
}
