import CarburantsKit
import SwiftUI
import WidgetKit

@main
struct CarburantsWidgetBundle: WidgetBundle {
    var body: some Widget {
        NearbyStationsWidget()
    }
}

/// The cheapest stations around: one on the small widget (also the size CarPlay shows), 3 on the medium,
/// 6 on the large, 8 on the extra large (iPad, iPhone Duo unfolded), and the best price on the Lock Screen.
struct NearbyStationsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NearbyStations", intent: StationsIntent.self, provider: StationsProvider()) { entry in
            StationsWidgetView(entry: entry)
        }
        .configurationDisplayName("Stations à proximité")
        .description("Les stations les moins chères autour de vous, avec leur prix.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryRectangular, .accessoryInline, .accessoryCircular,
        ])
    }
}

struct StationsWidgetView: View {
    let entry: StationsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if isAccessory { Color.clear } else { Color(.systemBackground) }
            }
    }

    private var isAccessory: Bool {
        family == .accessoryRectangular || family == .accessoryInline || family == .accessoryCircular
    }

    @ViewBuilder private var content: some View {
        if entry.state != .ready || entry.stations.isEmpty {
            EmptyWidget(entry: entry, family: family)
        } else {
            switch family {
            case .systemSmall: SmallWidget(entry: entry)
            case .systemMedium: ListWidget(entry: entry, count: 3)
            case .systemLarge: ListWidget(entry: entry, count: 6)
            case .systemExtraLarge: ListWidget(entry: entry, count: 8, columns: 2)
            case .accessoryRectangular: RectangularWidget(entry: entry)
            case .accessoryInline: InlineWidget(entry: entry)
            case .accessoryCircular: CircularWidget(entry: entry)
            default: SmallWidget(entry: entry)
            }
        }
    }
}

private func stationURL(_ station: Station) -> URL {
    URL(string: "carburants://station/\(station.id)")!
}

// MARK: - Home Screen

private struct SmallWidget: View {
    let entry: StationsEntry

    var body: some View {
        let station = entry.stations[0]
        let best = station.best(entry.fuels)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                StationLogo(station, size: 30)
                Spacer()
                if let best { FuelBadge(best.fuel) }
            }
            Spacer(minLength: 4)
            if let best {
                PriceText(best.price, font: .system(.title, design: .rounded))
                    .foregroundStyle(.green)
                    .minimumScaleFactor(0.7)
            }
            Text(station.name)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 3) {
                if let distance = station.distanceKm { Text("\(Format.distance(distance)) ·") }
                Text(entry.updated, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .widgetURL(stationURL(station))
    }
}

private struct ListWidget: View {
    let entry: StationsEntry
    let count: Int
    var columns = 1

    var body: some View {
        let stations = Array(entry.stations.prefix(count))
        let cheapest = stations.first?.best(entry.fuels)?.price
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "fuelpump.fill")
                Text(entry.fuels.count == 1 ? "\(entry.fuels[0].label) à proximité" : "À proximité")
                Spacer()
                Text(entry.updated, style: .relative)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 6) {
                ForEach(stations) { station in
                    Link(destination: stationURL(station)) {
                        WidgetRow(station: station, fuels: entry.fuels, cheapest: station.best(entry.fuels)?.price == cheapest)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct WidgetRow: View {
    let station: Station
    let fuels: [Fuel]
    let cheapest: Bool

    var body: some View {
        HStack(spacing: 10) {
            StationLogo(station, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(station.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text([station.distanceKm.map(Format.distance), Opening.of(station)?.text].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let best = station.best(fuels) {
                VStack(alignment: .trailing, spacing: 1) {
                    PriceText(best.price, font: .callout)
                        .foregroundStyle(cheapest ? .green : .primary)
                    if fuels.count > 1 { FuelBadge(best.fuel) }
                }
            }
        }
    }
}

// MARK: - Lock Screen

private struct RectangularWidget: View {
    let entry: StationsEntry

    var body: some View {
        let station = entry.stations[0]
        VStack(alignment: .leading, spacing: 0) {
            if let best = station.best(entry.fuels) {
                Label("\(best.fuel.short) · \(station.distanceKm.map(Format.distance) ?? "")", systemImage: "fuelpump.fill")
                    .font(.caption2)
                Text(Format.price(best.price))
                    .font(.headline)
                    .monospacedDigit()
                    .widgetAccentable()
            }
            Text(station.name)
                .font(.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(stationURL(station))
    }
}

private struct InlineWidget: View {
    let entry: StationsEntry

    var body: some View {
        let station = entry.stations[0]
        if let best = station.best(entry.fuels) {
            Label("\(Format.price(best.price)) · \(station.name)", systemImage: "fuelpump.fill")
        } else {
            Label(station.name, systemImage: "fuelpump.fill")
        }
    }
}

private struct CircularWidget: View {
    let entry: StationsEntry

    var body: some View {
        let station = entry.stations[0]
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "fuelpump.fill").font(.caption2)
                if let best = station.best(entry.fuels) {
                    // "1,75": the third decimal does not fit.
                    Text(best.price.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "fr_FR"))))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.6)
                        .widgetAccentable()
                }
            }
        }
        .widgetURL(stationURL(station))
    }
}

// MARK: - Empty

private struct EmptyWidget: View {
    let entry: StationsEntry
    let family: WidgetFamily

    private var symbol: String {
        switch entry.state {
        case .noLocation: "location.slash"
        case .failed: "wifi.exclamationmark"
        case .ready: "fuelpump.slash"
        }
    }

    private var text: String {
        switch entry.state {
        case .noLocation: "Ouvrez Carburants pour autoriser la localisation."
        case .failed: "Prix indisponibles pour le moment."
        case .ready: "Aucune station \(Format.fuels(entry.fuels)) à proximité."
        }
    }

    var body: some View {
        if family == .accessoryInline {
            Label("Carburants", systemImage: symbol)
        } else if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: symbol)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(family == .accessoryRectangular ? .body : .title2)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview(as: .systemSmall) {
    NearbyStationsWidget()
} timeline: {
    StationsEntry.sample
}

#Preview(as: .systemMedium) {
    NearbyStationsWidget()
} timeline: {
    StationsEntry.sample
}
