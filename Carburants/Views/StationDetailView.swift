import CarburantsKit
import SwiftUI

/// One station, as a place card in Plans: the name in big type with a close button, the directions button, a strip
/// of key facts (hours, distance, price), then your fuels, the others, hours, services and the address.
struct StationDetailView: View {
    let station: Station
    let fuels: [Fuel]
    var cheapest = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                header
                DirectionsButton(station: station)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                FactsStrip(station: station, fuels: fuels, cheapest: cheapest)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
            }
            .listRowBackground(Color.clear)

            let yours = fuels.filter { station.fuels[$0] != nil && station.sells($0) }
            if !yours.isEmpty {
                Section("Vos carburants") {
                    ForEach(yours) { FuelPriceRow(fuel: $0, price: station.fuels[$0]) }
                }
            }

            let others = Fuel.allCases.filter { !fuels.contains($0) && station.sells($0) }
            if !others.isEmpty {
                Section("Autres carburants") {
                    ForEach(others) { FuelPriceRow(fuel: $0, price: station.fuels[$0]) }
                }
            }

            hoursSection

            if !station.services.isEmpty || station.highway {
                Section("Services") {
                    if station.highway { ServiceRow(title: "Autoroute", symbol: "road.lanes") }
                    ForEach(station.services, id: \.self) { service in
                        ServiceRow(title: service, symbol: Self.symbol(for: service))
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Adresse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(station.prettyAddress)\n\(station.postcode) \(station.prettyCity)")
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
                .contextMenu {
                    Button("Copier l’adresse", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = "\(station.prettyAddress), \(station.postcode) \(station.prettyCity)"
                    }
                }
            } footer: {
                Text("Prix publiés par le ministère de l’Économie (data.economie.gouv.fr).")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .navigationTitle(station.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            // The name is in big type in the card itself, as in Plans: none in the bar.
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(
                    item: NavigationApp.appleMaps.url(for: station),
                    subject: Text(station.name),
                    message: Text(shareMessage)
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Partager")
                Button(role: .close) { dismiss() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(station.name)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(station.highway ? "Station-service · Autoroute" : "Station-service · \(station.prettyCity)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            StationLogo(station, size: 56)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
    }

    private var shareMessage: String {
        guard let best = station.best(fuels) else { return station.prettyAddress }
        return "\(best.fuel.label) à \(Format.price(best.price)) — \(station.prettyAddress), \(station.prettyCity)"
    }

    @ViewBuilder private var hoursSection: some View {
        let today = Opening.now().day
        if Opening.alwaysOpen(station.hours) {
            Section("Horaires") { ServiceRow(title: "Ouvert 24h/24", symbol: "clock.fill", tint: .green) }
        } else if !station.hours.isEmpty || station.automate24 {
            Section {
                ForEach(station.hours, id: \.day) { day in
                    LabeledContent {
                        Text(Self.ranges(day)).monospacedDigit()
                    } label: {
                        Text(Opening.dayNames.indices.contains(day.day - 1) ? Opening.dayNames[day.day - 1] : "Jour \(day.day)")
                    }
                    .fontWeight(day.day == today ? .semibold : .regular)
                }
                if station.automate24 {
                    ServiceRow(title: "Automate 24h/24", symbol: "creditcard.fill", tint: .orange)
                }
            } header: {
                Text("Horaires")
            }
        }
    }

    private static func ranges(_ day: DayHours) -> String {
        if day.closed || day.ranges.isEmpty { return "Fermé" }
        return day.ranges.map { "\($0.open)–\($0.close)" }.joined(separator: ", ")
    }

    private static func symbol(for service: String) -> String {
        let key = TextCase.key(service)
        let symbols: [(String, String)] = [
            ("lavage", "drop.fill"), ("boutique", "bag.fill"), ("restauration", "fork.knife"), ("bar", "cup.and.saucer.fill"),
            ("toilettes", "toilet.fill"), ("wifi", "wifi"), ("dab", "banknote.fill"), ("distributeur", "banknote.fill"),
            ("gonflage", "gauge.with.dots.needle.33percent"), ("electrique", "bolt.car.fill"), ("gaz", "flame.fill"),
            ("colis", "shippingbox.fill"), ("location", "key.fill"), ("poidslourd", "truck.box.fill"), ("campingcar", "bus.fill"),
            ("douche", "shower.fill"), ("adblue", "drop.triangle.fill"), ("aspiration", "wind"), ("bebe", "figure.and.child.holdinghands"),
        ]
        return symbols.first { key.contains($0.0) }?.1 ?? "checkmark.circle"
    }
}

/// A fuel with its price and freshness, or its shortage.
struct FuelPriceRow: View {
    let fuel: Fuel
    let price: FuelPrice?

    var body: some View {
        HStack(spacing: 12) {
            FuelBadge(fuel, large: true)
                .frame(minWidth: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(fuel.summary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let value = price?.price, price?.available == true {
                PriceText(value, font: .body)
            } else if price?.rupture != nil {
                Text("Rupture").fontWeight(.semibold).foregroundStyle(.red)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String? {
        guard let price else { return nil }
        if price.rupture != nil { return price.ruptureSince.map { "Depuis \(Format.since($0))" } }
        return price.updated.map { "Mis à jour \(Format.ago($0))" }
    }
}

/// Plans' strip under the buttons: a few facts side by side, a small grey title over each, thin rules between.
private struct FactsStrip: View {
    let station: Station
    let fuels: [Fuel]
    let cheapest: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if let opening = Opening.of(station) {
                fact("Horaires") {
                    Text(Self.status(opening))
                        .foregroundStyle(opening.state.color)
                }
                rule
            }
            if let distance = station.distanceKm {
                fact("Distance") { Text(Format.distance(distance)) }
                rule
            }
            fact(fuels.count > 1 ? (station.best(fuels)?.fuel.short ?? "Prix") : "Prix") {
                if let best = station.best(fuels) {
                    Text(Format.price(best.price))
                        .monospacedDigit()
                        .foregroundStyle(cheapest ? .green : .primary)
                } else {
                    Text(station.inShortage(fuels) ? "Rupture" : "—")
                        .foregroundStyle(station.inShortage(fuels) ? .red : .secondary)
                }
            }
        }
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func fact<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            value()
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var rule: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 0.5, height: 32)
            .padding(.top, 2)
    }

    /// The first word of the status ("Ouvert", "Fermé"), or "24h/24".
    private static func status(_ opening: Opening) -> String {
        switch opening.state {
        case .always: "24h/24"
        case .automate: "Automate"
        case .open, .closed: opening.text.components(separatedBy: " · ").first ?? opening.text
        }
    }
}

/// A service with its symbol in a coloured rounded square, as Settings and Plans list features.
private struct ServiceRow: View {
    let title: String
    let symbol: String
    var tint: Color = .blue

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

#Preview {
    NavigationStack {
        StationDetailView(station: Station.samples[0], fuels: [.gazole, .e10])
    }
}
