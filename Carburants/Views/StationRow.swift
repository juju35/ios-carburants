import CarburantsKit
import SwiftUI

/// A result row, as in Plans: logo tile, name, distance and town, the opening status with only its first word in
/// colour; the price of the cheapest of your fuels on the right, in green with a tag for the cheapest station.
struct StationRow: View {
    let station: Station
    let fuels: [Fuel]
    let cheapest: Bool

    var body: some View {
        HStack(spacing: 14) {
            StationLogo(station, size: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(place)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let opening = Opening.of(station) {
                    OpeningLine(opening: opening)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            price
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// "1,2 km · Rennes", as Plans puts the distance before the place.
    private var place: String {
        [station.distanceKm.map(Format.distance), station.prettyCity].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private var price: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let best = station.best(fuels) {
                PriceText(best.price)
                    .foregroundStyle(cheapest ? .green : .primary)
                if cheapest {
                    CheapestTag()
                } else if fuels.count > 1 {
                    FuelBadge(best.fuel)
                }
            } else if station.inShortage(fuels) {
                Text("Rupture")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            } else {
                Text("—")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// "Ouvert · ferme à 21:00" with "Ouvert" in the status colour and the rest in grey, as Plans writes hours.
struct OpeningLine: View {
    let opening: Opening

    var body: some View {
        let parts = opening.text.components(separatedBy: " · ")
        let status = Text(parts[0]).foregroundStyle(opening.state.color)
        if parts.count > 1 {
            Text("\(status)\(Text(" · " + parts.dropFirst().joined(separator: " · ")).foregroundStyle(.secondary))")
        } else {
            status
        }
    }
}

/// Small green capsule under the cheapest price.
struct CheapestTag: View {
    var body: some View {
        Text("Moins cher")
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.green)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.green.opacity(0.15), in: Capsule())
    }
}

#Preview {
    List(Station.samples) { StationRow(station: $0, fuels: [.gazole, .e10], cheapest: $0.id == 35000001) }
        .listStyle(.plain)
}
