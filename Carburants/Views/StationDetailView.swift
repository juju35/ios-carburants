import CarburantsKit
import SwiftUI

/// One station, as a place card in Plans: name and address, a big directions button, your fuels, the others,
/// hours and services.
struct StationDetailView: View {
    let station: Station
    let fuels: [Fuel]

    var body: some View {
        List {
            Section {
                header
                DirectionsButton(station: station)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
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
                    if station.highway { Label("Autoroute", systemImage: "road.lanes") }
                    ForEach(station.services, id: \.self) { service in
                        Label(service, systemImage: Self.symbol(for: service))
                    }
                }
            }

            Section {
                LabeledContent("Adresse") {
                    Text("\(station.prettyAddress)\n\(station.postcode) \(station.prettyCity)")
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("Prix publiés par le ministère de l’Économie (data.economie.gouv.fr).")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(station.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 14) {
            StationLogo(station, size: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(station.name)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text([station.distanceKm.map(Format.distance), station.prettyCity].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let opening = Opening.of(station) {
                    Text(opening.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(opening.state.color)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
    }

    @ViewBuilder private var hoursSection: some View {
        let today = Opening.now().day
        if Opening.alwaysOpen(station.hours) {
            Section("Horaires") { Label("Ouvert 24h/24", systemImage: "clock") }
        } else if !station.hours.isEmpty || station.automate24 {
            Section {
                ForEach(station.hours, id: \.day) { day in
                    LabeledContent {
                        Text(Self.ranges(day)).monospacedDigit()
                    } label: {
                        Text(Opening.dayNames[day.day - 1])
                    }
                    .fontWeight(day.day == today ? .semibold : .regular)
                }
                if station.automate24 {
                    Label("Automate 24h/24", systemImage: "creditcard")
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

#Preview {
    NavigationStack {
        StationDetailView(station: Station.samples[0], fuels: [.gazole, .e10])
    }
}
