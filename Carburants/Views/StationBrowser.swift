import CarburantsKit
import SwiftUI

/// The list of stations and, pushed over it, a station's detail; in the sheet or the side panel.
struct StationBrowser: View {
    @Bindable var model: StationsModel
    @State private var path: [Station.ID] = []
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack(path: $path) {
            content
                .modifier(ClearNavigationBackground())
                .navigationTitle("Stations")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .navigationDestination(for: Station.ID.self) { id in
                    if let station = model.station(id) {
                        StationDetailView(station: station, fuels: model.fuels)
                            .modifier(ClearNavigationBackground())
                    } else {
                        ContentUnavailableView("Station introuvable", systemImage: "fuelpump.slash")
                    }
                }
        }
        .sheet(isPresented: $model.showsFuelPicker) {
            FuelPickerView(selection: model.fuels) { model.setFuels($0) }
        }
        .onAppear {
            // Opened from a widget before this view existed.
            if let id = model.selectedID { path = [id] }
            if Demo.isOn, Demo.screen == .fuels { model.showsFuelPicker = true }
        }
        .onChange(of: model.selectedID) { _, id in
            if let id, path.last != id { path = [id] }
        }
        .onChange(of: path) { _, path in
            model.selectedID = path.last
        }
    }

    // MARK: - States

    @ViewBuilder private var content: some View {
        let location = model.location
        if !Demo.isOn, location.authorization == .notDetermined {
            ContentUnavailableView {
                Label("Stations à proximité", systemImage: "location.circle.fill")
            } description: {
                Text("Carburants utilise votre position pour trouver les stations les plus proches et leurs prix.")
            } actions: {
                Button("Autoriser la localisation") { location.requestPermission() }
                    .buttonStyle(.borderedProminent)
            }
        } else if !Demo.isOn, location.isDenied {
            ContentUnavailableView {
                Label("Localisation désactivée", systemImage: "location.slash.fill")
            } description: {
                Text("Autorisez Carburants à utiliser votre position dans les Réglages.")
            } actions: {
                Button("Ouvrir les Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        } else if model.stations != nil {
            if model.visible.isEmpty {
                ContentUnavailableView {
                    Label("Aucune station", systemImage: "fuelpump.slash")
                } description: {
                    Text(
                        "Aucune station \(Format.fuels(model.fuels)) dans un rayon de \(model.radiusKm) km. "
                            + "Les prix couvrent la France uniquement."
                    )
                }
            } else {
                list
            }
        } else if case let .failed(message) = model.phase {
            ContentUnavailableView {
                Label("Prix indisponibles", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { model.refresh() }
            }
        } else {
            ProgressView("Recherche des stations…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(model.visible) { station in
                    NavigationLink(value: station.id) {
                        StationRow(station: station, fuels: model.fuels, cheapest: model.isCheapest(station))
                    }
                }
            } footer: {
                footer
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.refresh()?.value }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if let date = model.updatedAt {
                // Kept current between searches.
                TimelineView(.everyMinute) { _ in
                    Text("Mis à jour \(Format.ago(date)) · rayon de \(model.radiusKm) km")
                }
            }
            Text("Prix publiés par le ministère de l’Économie")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                model.showsFuelPicker = true
            } label: {
                Label(Format.fuels(model.fuels), systemImage: "fuelpump")
                    .labelStyle(.titleAndIcon)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Trier par", selection: Binding(get: { model.sort }, set: { model.setSort($0) })) {
                    Label("Prix", systemImage: "eurosign").tag(StationOrder.price)
                    Label("Distance", systemImage: "location").tag(StationOrder.distance)
                }
            } label: {
                Label("Trier", systemImage: "arrow.up.arrow.down")
            }
        }
    }
}

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
                } else {
                    Text("Rupture")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
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

/// The material or glass behind the list (sheet, side panel) shows through, instead of the navigation stack's white.
private struct ClearNavigationBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.containerBackground(.clear, for: .navigation)
        } else {
            content
        }
    }
}
