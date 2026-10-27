import CarburantsKit
import MapKit
import SwiftUI

/// Stations ordered by price or distance, or filtered by a search query.
///
/// On iPhone, this view is presented inside an interactive sheet; on iPad and Mac, in a floating panel;
/// on iPhone Duo folded, in one of the two halves.
struct StationBrowser: View {
    @Bindable var model: StationsModel
    var inlineSearch: Bool = true
    var onCollapse: (() -> Void)?

    @State private var path: [Station.ID] = []
    @State private var completer = TownSearchCompleter()
    @FocusState private var isSearchFieldFocused: Bool
    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack(path: $path) {
            content
                .modifier(ClearNavigationBackground())
                .navigationTitle(inlineSearch ? "" : navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .modifier(SearchableDrawerModifier(
                    enabled: !inlineSearch,
                    text: $model.filterText,
                    isSearching: $model.isSearching,
                    onSubmit: submitSearchQuery
                ))
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
            FuelPickerView(selection: model.fuels, navigationApp: model.navigationApp) { fuels, app in
                model.setFuels(fuels)
                model.setNavigationApp(app)
            }
        }
        .onAppear {
            // Opened from a widget before this view existed.
            if let id = model.selectedID { path = [id] }
            if Demo.isOn, Demo.screen == .fuels { model.showsFuelPicker = true }
        }
        .onChange(of: model.filterText) { _, newText in
            completer.query = newText
            if !newText.isEmpty {
                model.isSearching = true
            }
        }
        .onChange(of: isSearchFieldFocused) { _, focused in
            if focused, !model.isSearching {
                model.isSearching = true
            }
        }
        .onChange(of: model.isSearching) { _, searching in
            if isSearchFieldFocused != searching {
                isSearchFieldFocused = searching
            }
        }
        .onChange(of: model.selectedID) { _, id in
            if let id, path.last != id { path = [id] }
        }
        .onChange(of: path) { _, path in
            model.selectedID = path.last
        }
    }

    private var navigationTitle: String {
        if let custom = model.customTownName {
            return custom
        }
        return "Stations"
    }

    private func selectTown(_ suggestion: TownSuggestion) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isSearchFieldFocused = false
        model.isSearching = false
        dismissSearch()
        Task {
            if let resolved = await TownSearchCompleter.resolve(suggestion: suggestion) {
                model.searchTown(name: resolved.name, coordinate: resolved.coordinate)
            }
        }
    }

    private func submitSearchQuery() {
        let query = model.filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isSearchFieldFocused = false
        model.isSearching = false
        dismissSearch()
        Task {
            if let resolved = await TownSearchCompleter.resolve(query: query) {
                model.searchTown(name: resolved.name, coordinate: resolved.coordinate)
            }
        }
    }

    // MARK: - States

    @ViewBuilder private var content: some View {
        let location = model.location
        if model.customLocation == nil, !Demo.isOn, location.authorization == .notDetermined {
            ContentUnavailableView {
                Label("Position requise", systemImage: "location.slash")
            } description: {
                Text("Pour afficher les stations les plus proches et leurs prix.")
            } actions: {
                Button("Autoriser la localisation") {
                    location.requestPermission()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if model.customLocation == nil, !Demo.isOn, location.isDenied {
            ContentUnavailableView {
                Label("Position refusée", systemImage: "location.slash")
            } description: {
                Text("Activez la localisation dans Réglages pour voir les stations autour de vous.")
            } actions: {
                Button("Ouvrir les Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if model.customLocation == nil, !Demo.isOn, location.failed {
            ContentUnavailableView {
                Label("Position introuvable", systemImage: "location.slash")
            } description: {
                Text("Carburants n’arrive pas à déterminer votre position. Vérifiez que le mode Avion est désactivé.")
            } actions: {
                Button("Réessayer") {
                    location.retry()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if model.stations == nil && model.phase == .loading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let stations = model.stations, stations.isEmpty {
            ContentUnavailableView {
                Label("Aucune station", systemImage: "fuelpump.slash")
            } description: {
                Text(
                    model.customTownName != nil
                        ? "Aucune station dans un rayon de \(model.radiusKm) km autour de \(model.customTownName ?? "")."
                        : "Aucune station \(Format.fuels(model.fuels)) dans un rayon de \(model.radiusKm) km. "
                            + "Augmentez le rayon ou modifiez vos carburants."
                )
            } actions: {
                if model.customTownName != nil {
                    Button("Ma position") {
                        model.resetToCurrentLocation()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Carburants") {
                        model.showsFuelPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else if model.stations == nil, case let .failed(message) = model.phase {
            ContentUnavailableView {
                Label("Impossible de charger", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") {
                    model.refresh()
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            stationList
        }
    }

    private var stationList: some View {
        List {
            if let customTown = model.customTownName {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recherche autour de")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(customTown)
                                .font(.headline)
                        }
                        Spacer()
                        Button("Ma position") {
                            model.resetToCurrentLocation()
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }

            if model.isSearching {
                TownSuggestionsSection(suggestions: completer.suggestions, onSelect: selectTown)
            }

            Section {
                ForEach(model.visible) { station in
                    NavigationLink(value: station.id) {
                        StationRow(station: station, fuels: model.fuels, cheapest: model.isCheapest(station))
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            footer
        }
        .listStyle(.plain)
        .overlay {
            if model.visible.isEmpty, !model.filterText.isEmpty, completer.suggestions.isEmpty {
                ContentUnavailableView.search(text: model.filterText)
            }
        }
        .refreshable {
            model.refresh()
        }
    }

    private var footer: some View { BrowserFooter(model: model) }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if let onCollapse {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onCollapse) {
                    Image(systemName: "sidebar.leading")
                }
            }
        } else if inlineSearch {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text(navigationTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .allowsHitTesting(false)
                        .accessibilityHeading(.h1)
                    InlineSearchField(
                        text: $model.filterText,
                        isSearching: $model.isSearching,
                        isFocused: $isSearchFieldFocused,
                        onSubmit: submitSearchQuery
                    )
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                if inlineSearch && (isSearchFieldFocused || model.isSearching) {
                    Button("Annuler") {
                        model.filterText = ""
                        isSearchFieldFocused = false
                        model.isSearching = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                } else {
                    Menu {
                        Picker("Trier par", selection: Binding(get: { model.sort }, set: { model.setSort($0) })) {
                            Label("Prix", systemImage: "eurosign").tag(StationOrder.price)
                            Label("Distance", systemImage: "location").tag(StationOrder.distance)
                        }

                        Section("Application d’itinéraire") {
                            Picker("Navigation", selection: Binding(
                                get: { model.navigationApp },
                                set: { model.setNavigationApp($0) }
                            )) {
                                ForEach(NavigationApp.allCases) { app in
                                    Label(app.title, systemImage: app.symbol).tag(app)
                                }
                            }
                        }
                    } label: {
                        Label("Trier", systemImage: "arrow.up.arrow.down")
                    }

                    Button {
                        model.showsFuelPicker = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Préférences")
                }
            }
        }
    }
}

/// Compact inline search field used in the toolbar.
private struct InlineSearchField: View {
    @Binding var text: String
    @Binding var isSearching: Bool
    @FocusState.Binding var isFocused: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.footnote)
            TextField(
                "Rechercher",
                text: $text
            )
            .textFieldStyle(.plain)
            .font(.subheadline)
            .focused($isFocused)
            .submitLabel(.search)
            .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .contentShape(Capsule())
        .simultaneousGesture(TapGesture().onEnded {
            if !isFocused {
                isFocused = true
            }
        })
        .onChange(of: isFocused) { _, focused in
            if focused, !isSearching {
                isSearching = true
            }
        }
    }
}

/// Applies the standard drawer searchable when not in inline mode.
private struct SearchableDrawerModifier: ViewModifier {
    let enabled: Bool
    @Binding var text: String
    @Binding var isSearching: Bool
    let onSubmit: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .searchable(text: $text, isPresented: $isSearching, prompt: "Rechercher")
                .onSubmit(of: .search, onSubmit)
        } else {
            content
        }
    }
}

/// Strip the navigation bar's background so the scroll view shows underneath it when appropriate.
private struct ClearNavigationBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

/// Pulls the data feed's date and the current radius, with buttons to widen or reset.
private struct BrowserFooter: View {
    @Bindable var model: StationsModel

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if let updated = model.updatedAt {
                    Text("Données gouvernementales \(Format.ago(updated)).")
                }
                Text("Rayon de recherche : \(model.radiusKm) km.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}
