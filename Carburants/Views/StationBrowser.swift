import CarburantsKit
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
            root
                .navigationDestination(for: Station.ID.self) { id in
                    if let station = model.station(id) {
                        StationDetailView(station: station, fuels: model.fuels, cheapest: model.isCheapest(station))
                            .modifier(ClearNavigationBackground())
                    } else {
                        ContentUnavailableView("Station introuvable", systemImage: "fuelpump.slash")
                    }
                }
        }
        .modifier(DisableVerticalToolbarModifier())
        .sheet(isPresented: $model.showsFuelPicker) {
            FuelPickerView(
                selection: model.fuels, navigationApp: model.navigationApp, searchRadiusKm: model.searchRadiusKm
            ) { fuels, app, radius in
                model.setFuels(fuels)
                model.setNavigationApp(app)
                model.setSearchRadius(radius)
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
            if !path.isEmpty {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                isSearchFieldFocused = false
            }
        }
    }

    /// The list with its bar; the bar gives way to the stations as the list scrolls down, and comes back on the way up.
    private var root: some View {
        content
            .modifier(ClearNavigationBackground())
            .navigationTitle(inlineSearch ? "" : navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
            .modifier(DisableVerticalToolbarModifier())
            .modifier(SearchableDrawerModifier(
                enabled: !inlineSearch,
                text: $model.filterText,
                isSearching: $model.isSearching,
                onSubmit: submitSearchQuery
            ))
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
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isSearchFieldFocused = false
        model.isSearching = false
        dismissSearch()
        let query = model.filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
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
                Button("Autoriser la position") {
                    location.start()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if model.customLocation == nil, !Demo.isOn, location.isDenied {
            ContentUnavailableView {
                Label("Position refusée", systemImage: "location.slash")
            } description: {
                Text("Autorisez l’accès dans Réglages pour situer les stations autour de vous.")
            } actions: {
                Button("Ouvrir Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if model.stations == nil, case let .failed(message) = model.phase {
            ContentUnavailableView {
                Label("Prix indisponibles", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") {
                    model.refresh()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if model.stations == nil {
            ContentUnavailableView {
                ProgressView().controlSize(.large)
            } description: {
                Text("Recherche des stations…")
            }
        } else if model.visible.isEmpty, model.filterText.isEmpty {
            ContentUnavailableView {
                Label("Aucune station", systemImage: "fuelpump")
            } description: {
                Text("Aucune station ne vend \(Format.fuels(model.fuels)) dans un rayon de \(model.radiusKm) km.")
            } actions: {
                Button("Changer les carburants") {
                    model.showsFuelPicker = true
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if let customTown = model.customTownName {
                CustomTownRow(town: customTown) {
                    model.resetToCurrentLocation()
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if model.isSearching {
                TownSuggestionsSection(suggestions: completer.suggestions, onSelect: selectTown)
            }

            Section {
                ForEach(model.visible) { station in
                    NavigationLink(value: station.id) {
                        StationRow(station: station, fuels: model.fuels, cheapest: model.isCheapest(station))
                    }
                    // Plans' result rows have no chevron.
                    .navigationLinkIndicatorVisibility(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 62 }
                }
            } header: {
                if !model.visible.isEmpty {
                    Text(listHeader)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            footer
        }
        .listStyle(.plain)
        // The capsules stay under the bar, as in Plans, instead of scrolling with the rows: as the list's first row
        // they slid under the bar's scroll edge on the Mac and iPad panel, half hidden and blurred.
        .safeAreaBar(edge: .top) {
            if !model.isSearching {
                QuickFilters(model: model)
                    .padding(.vertical, 6)
            }
        }
        .scrollDismissesKeyboard(.interactively)
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

    /// "6 stations · 10 km", as Plans counts its results.
    private var listHeader: String {
        let count = model.visible.count
        return "\(count) station\(count > 1 ? "s" : "") · \(model.radiusKm) km"
    }

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
                // The search field across the sheet, as in Plans.
                InlineSearchField(
                    text: $model.filterText,
                    isSearching: $model.isSearching,
                    isFocused: $isSearchFieldFocused,
                    onSubmit: submitSearchQuery
                )
                .frame(minWidth: 220, maxWidth: .infinity)
            }
        }

        if inlineSearch && (isSearchFieldFocused || model.isSearching || !model.filterText.isEmpty) {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Annuler") {
                    withAnimation(.smooth) {
                        model.filterText = ""
                        isSearchFieldFocused = false
                        model.isSearching = false
                    }
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }

        // Pinned: stays at the trailing edge whatever the width (iPhone Duo cover screen, resized window), as Plans
        // keeps its account button beside the search field.
        ToolbarItem(placement: .topBarPinnedTrailing) {
            Button {
                model.showsFuelPicker = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Préférences")
        }

        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                isSearchFieldFocused = false
                if model.filterText.isEmpty {
                    model.isSearching = false
                }
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
            }
            .accessibilityLabel("Masquer le clavier")
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.body.weight(.medium))
            TextField(
                "Station, ville, code postal",
                text: $text,
                onEditingChanged: { editing in
                    if editing {
                        isSearching = true
                        isFocused = true
                    }
                }
            )
            .textFieldStyle(.plain)
            .font(.body)
            .focused($isFocused)
            .submitLabel(.search)
            .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            if !isFocused {
                isFocused = true
            }
            isSearching = true
        }
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
                .searchable(text: $text, isPresented: $isSearching, prompt: "Station, ville, code postal")
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

/// Disables vertical toolbar rail on iPhone Duo cover screen so toolbar stays horizontal and content fills width.
struct DisableVerticalToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if !targetEnvironment(macCatalyst)
        content.toolbarVerticalBehavior(.disabled)
        #else
        content
        #endif
    }
}

/// Last update time and data credits at the bottom of the list.
private struct BrowserFooter: View {
    @Bindable var model: StationsModel

    var body: some View {
        VStack(spacing: 4) {
            if let date = model.updatedAt {
                Text("Mis à jour \(Format.ago(date))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Données gouvernementales (prix-carburants.gouv.fr)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

/// The town searched instead of the current position, with the way back to it, as a card at the top of the list.
private struct CustomTownRow: View {
    let town: String
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
            VStack(alignment: .leading, spacing: 1) {
                Text("Autour de")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(town)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onReset) {
                Label("Ma position", systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.blue)
        }
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
