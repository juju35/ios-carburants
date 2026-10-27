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
/// 5 on the large with multi-fuels (6 with single fuel), 8 on extra large, and Lock Screen accessories.
struct NearbyStationsWidget: Widget {
    private var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryRectangular, .accessoryInline, .accessoryCircular,
        ]
        if #available(iOS 27.0, *) {
            families.append(.systemExtraLargePortrait)
        }
        return families
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NearbyStations", intent: StationsIntent.self, provider: StationsProvider()) { entry in
            StationsWidgetView(entry: entry)
        }
        .configurationDisplayName("Stations à proximité")
        .description("Les stations autour de vous, avec leur prix.")
        .supportedFamilies(supportedFamilies)
    }
}

struct StationsWidgetView: View {
    let entry: StationsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if isAccessory {
                    Color.clear
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
    }

    private var isAccessory: Bool {
        family == .accessoryRectangular || family == .accessoryInline || family == .accessoryCircular
    }

    @ViewBuilder private var content: some View {
        Group {
            if entry.state != .ready || entry.stations.isEmpty {
                EmptyWidget(entry: entry, family: family)
            } else {
                switch family {
                case .systemSmall: SmallWidget(entry: entry)
                case .systemMedium: ListWidget(entry: entry, count: entry.fuels.count > 1 ? 2 : 3)
                case .systemLarge: ListWidget(entry: entry, count: entry.fuels.count > 1 ? 5 : 6)
                case .systemExtraLarge: ListWidget(entry: entry, count: 8, columns: 2)
                case .systemExtraLargePortrait: ListWidget(entry: entry, count: entry.fuels.count > 1 ? 8 : 10)
                case .accessoryRectangular: RectangularWidget(entry: entry)
                case .accessoryInline: InlineWidget(entry: entry)
                case .accessoryCircular: CircularWidget(entry: entry)
                default: SmallWidget(entry: entry)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        Group {
            if entry.fuels.count <= 1 {
                singleFuel(station: station)
            } else {
                multiFuel(station: station)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(stationURL(station))
    }

    private func singleFuel(station: Station) -> some View {
        let best = station.best(entry.fuels)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                StationLogo(station, size: 36)
                Spacer()
                if let best { FuelBadge(best.fuel) }
            }
            Spacer(minLength: 4)
            if let best {
                PriceText(best.price, font: .system(.title, design: .rounded))
                    .foregroundStyle(.green)
                    .minimumScaleFactor(0.7)
            }
            Text(station.name).font(.footnote.weight(.semibold)).lineLimit(2)
            HStack(spacing: 3) {
                openingIcon(station, date: entry.date)
                if let distance = station.distanceKm { Text("\(Format.distance(distance)) ·") }
                Text(entry.updated, style: .relative)
            }
            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func multiFuel(station: Station) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                StationLogo(station, size: 34)
                Spacer()
                HStack(spacing: 3) {
                    openingIcon(station, date: entry.date)
                    if let distance = station.distanceKm { Text("\(Format.distance(distance)) ·") }
                    Text(entry.updated, style: .relative)
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 2)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(entry.fuels.prefix(3), id: \.self) { fuel in
                    HStack {
                        FuelBadge(fuel)
                            .fixedSize()
                        Spacer()
                        if let price = station.price(fuel) {
                            PriceText(price, font: .callout)
                                .foregroundStyle(entry.isCheapest(price: price, for: fuel) ? .green : .primary)
                                .fixedSize()
                        } else if station.inShortage([fuel]) {
                            Text("Rupture").font(.caption2.weight(.medium)).foregroundStyle(.red)
                                .fixedSize()
                        } else {
                            Text("—").font(.caption2).foregroundStyle(.secondary)
                                .fixedSize()
                        }
                    }
                }
            }
            Spacer(minLength: 2)
            Text(station.name).font(.footnote.weight(.semibold)).lineLimit(2)
        }
    }
}

private struct ListWidget: View {
    let entry: StationsEntry
    let count: Int
    var columns = 1

    var body: some View {
        let stations = Array(entry.stations.prefix(count))
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 4)
            if columns > 1 {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 8) {
                    ForEach(stations) { station in
                        Link(destination: stationURL(station)) {
                            WidgetRow(station: station, fuels: entry.fuels, entry: entry, date: entry.date)
                        }
                    }
                }
            } else {
                ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                    Spacer(minLength: 2)
                    Link(destination: stationURL(station)) {
                        WidgetRow(station: station, fuels: entry.fuels, entry: entry, date: entry.date)
                    }
                    Spacer(minLength: 2)
                    if index < stations.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.order == .distance ? "location.fill" : "fuelpump.fill")
            Text(entry.fuels.count == 1 ? "\(entry.fuels[0].label) à proximité" : "Stations à proximité")
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(entry.updated, style: .relative)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}

private struct WidgetRow: View {
    let station: Station
    let fuels: [Fuel]
    let entry: StationsEntry
    let date: Date

    var body: some View {
        Group {
            if fuels.count > 1 {
                multiFuelRow
            } else {
                singleFuelRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var singleFuelRow: some View {
        HStack(spacing: 10) {
            StationLogo(station, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(station.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    openingIcon(station, date: date)
                    if let distance = station.distanceKm {
                        Text(Format.distance(distance))
                    }
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let fuel = fuels.first {
                fuelPriceView(fuel: fuel)
                    .fixedSize()
            }
        }
    }

    private var multiFuelRow: some View {
        HStack(alignment: .center, spacing: 10) {
            StationLogo(station, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(station.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    HStack(spacing: 4) {
                        openingIcon(station, date: date)
                        if let distance = station.distanceKm {
                            Text(Format.distance(distance))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .layoutPriority(1)
                }
                HStack(spacing: 8) {
                    ForEach(fuels.prefix(4), id: \.self) { fuel in
                        HStack(spacing: 4) {
                            FuelBadge(fuel)
                                .fixedSize()
                            fuelPriceView(fuel: fuel)
                                .fixedSize()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fuelPriceView(fuel: Fuel) -> some View {
        if let price = station.price(fuel) {
            PriceText(price, font: .subheadline.weight(.semibold))
                .foregroundStyle(entry.isCheapest(price: price, for: fuel) ? .green : .primary)
                .lineLimit(1)
        } else if station.inShortage([fuel]) {
            Text("Rupture")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .lineLimit(1)
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

@ViewBuilder
private func openingIcon(_ station: Station, date: Date) -> some View {
    if let opening = Opening.of(station, at: date) {
        switch opening.state {
        case .always, .automate:
            Image(systemName: "24.circle.fill")
                .foregroundStyle(.orange)
        case .open:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .closed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Lock Screen

private struct RectangularWidget: View {
    let entry: StationsEntry

    var body: some View {
        let station = entry.stations[0]
        if entry.fuels.count <= 1 {
            singleFuel(station: station)
        } else {
            multiFuel(station: station)
        }
    }

    private func singleFuel(station: Station) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let best = station.best(entry.fuels) {
                Label("\(best.fuel.short) · \(station.distanceKm.map(Format.distance) ?? "")", systemImage: "fuelpump.fill")
                    .font(.caption2)
                Text(Format.price(best.price)).font(.headline).monospacedDigit().widgetAccentable()
            }
            Text(station.name).font(.caption).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(stationURL(station))
    }

    private func multiFuel(station: Station) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(station.name).font(.caption2.weight(.semibold)).lineLimit(1)
                Spacer()
                if let distance = station.distanceKm {
                    Text(Format.distance(distance)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                ForEach(entry.fuels.prefix(2), id: \.self) { fuel in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(fuel.short).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        if let price = station.price(fuel) {
                            Text(Format.price(price)).font(.subheadline.weight(.semibold)).monospacedDigit().widgetAccentable()
                        } else {
                            Text("—").font(.subheadline)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(stationURL(station))
    }
}

private struct InlineWidget: View {
    let entry: StationsEntry

    var body: some View {
        let station = entry.stations[0]
        if entry.fuels.count > 1,
           let fuel1 = entry.fuels.first, let price1 = station.price(fuel1),
           let fuel2 = entry.fuels.dropFirst().first, let price2 = station.price(fuel2) {
            Label("\(fuel1.short): \(Format.price(price1)) · \(fuel2.short): \(Format.price(price2))", systemImage: "fuelpump.fill")
        } else if let best = station.best(entry.fuels) {
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
                if entry.fuels.count > 1,
                   let fuel1 = entry.fuels.first, let price1 = station.price(fuel1),
                   let fuel2 = entry.fuels.dropFirst().first, let price2 = station.price(fuel2) {
                    Text(price1.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "fr_FR"))))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .widgetAccentable()
                    Text(price2.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "fr_FR"))))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "fuelpump.fill").font(.caption2)
                    if let best = station.best(entry.fuels) {
                        Text(best.price.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "fr_FR"))))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .minimumScaleFactor(0.6)
                            .widgetAccentable()
                    }
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
