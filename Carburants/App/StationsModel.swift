import CarburantsKit
// swiftlint:disable:next unused_import - also reached through another import, kept explicit for Swift 6
import CoreLocation
import Observation
import WidgetKit

/// Stations around the phone or a selected town, shared by every window and CarPlay.
@MainActor
@Observable
final class StationsModel {
    static let shared = StationsModel()

    enum Phase: Equatable {
        case idle, loading
        case failed(String)
    }

    let location = LocationProvider()

    private(set) var fuels: [Fuel] {
        didSet { recomputeDerivedState() }
    }
    private(set) var sort: StationOrder {
        didSet { recomputeDerivedState() }
    }
    private(set) var navigationApp: NavigationApp
    /// Chosen search radius; `radiusKm` is the one effectively used (widened when few stations are found).
    private(set) var searchRadiusKm: Int
    /// nil until a first search returns.
    private(set) var stations: [Station]? {
        didSet { recomputeDerivedState() }
    }
    private(set) var radiusKm = StationRepository.radiusKm
    private(set) var phase: Phase = .idle
    private(set) var updatedAt: Date?
    /// The station shown on the map and in the detail.
    var selectedID: Station.ID?
    /// The fuel picker, opened from the list's toolbar (and by the demo mode).
    var showsFuelPicker = false

    /// Filter query typed in the search bar.
    var filterText: String = "" {
        didSet { recomputeDerivedState() }
    }
    /// Whether the user is currently typing in the search bar.
    var isSearching = false

    /// Whether the iPhone window or CarPlay app is currently visible on screen.
    private(set) var isIPhoneVisible = false
    private(set) var isCarPlayVisible = false
    private(set) var isCarPlayConnected = false

    var isAppVisible: Bool {
        isIPhoneVisible || isCarPlayVisible
    }

    /// When set, stations are searched around this town rather than user's GPS position.
    private(set) var customTownName: String?
    private(set) var customLocation: CLLocation?

    @ObservationIgnored private let preferences = Preferences.shared
    @ObservationIgnored private var fetchedAt: CLLocation?
    /// Where the stations on screen were searched (the snapshot is saved under it).
    @ObservationIgnored private var listCoordinate: CLLocationCoordinate2D?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var needsReloadOnNextFix = false

    // New search after 1 km or 10 minutes (the feed is refreshed every 10 minutes).
    private static let refetchMeters: CLLocationDistance = 1_000
    private static let refetchInterval: TimeInterval = 10 * 60
    // CoreLocation first hands over its last known fix, possibly hours old: not a place to search around.
    private static let maxFixAge: TimeInterval = 120

    private init() {
        if Demo.isOn {
            // Opening statuses at 9:41, the status bar's time, whenever the screenshots are taken.
            Opening.clock = { Opening.nineFortyOne }
            fuels = [.gazole, .e10]
            sort = .price
            navigationApp = .appleMaps
            searchRadiusKm = StationRepository.radiusKm
            stations = Station.samples
            updatedAt = .now.addingTimeInterval(-4 * 60)
            recomputeDerivedState()
            return
        }
        fuels = preferences.fuels
        sort = preferences.sort
        navigationApp = preferences.navigationApp
        searchRadiusKm = preferences.searchRadiusKm
        // Last list for an instant start, when recent and for the same fuels; distances refresh with the next search.
        if let snapshot = Snapshot.load(), snapshot.fuels == preferences.fuels, Date().timeIntervalSince(snapshot.date) < 30 * 60 {
            stations = snapshot.stations
            radiusKm = snapshot.radiusKm
            updatedAt = snapshot.date
            listCoordinate = CLLocationCoordinate2D(latitude: snapshot.latitude, longitude: snapshot.longitude)
        }
        recomputeDerivedState()
        location.onUpdate = { [weak self] location in self?.locationChanged(location) }
    }

    // MARK: - Derived

    private(set) var visible: [Station] = []
    private(set) var cheapestPrice: Double?

    private func recomputeDerivedState() {
        let sorted = StationSort.sorted(stations ?? [], by: sort, fuels: fuels)
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: .diacriticInsensitive, locale: .current)
        if query.isEmpty {
            visible = sorted
        } else {
            visible = sorted.filter { station in
                let city = station.city.folding(options: .diacriticInsensitive, locale: .current)
                let address = station.address.folding(options: .diacriticInsensitive, locale: .current)
                let name = station.name.folding(options: .diacriticInsensitive, locale: .current)
                let postcode = station.postcode
                return city.localizedCaseInsensitiveContains(query)
                    || address.localizedCaseInsensitiveContains(query)
                    || name.localizedCaseInsensitiveContains(query)
                    || postcode.contains(query)
            }
        }
        cheapestPrice = visible.compactMap { $0.best(fuels)?.price }.min()
    }

    func station(_ id: Station.ID?) -> Station? {
        guard let id else { return nil }
        if let found = stations?.first(where: { $0.id == id }) {
            return found
        }
        // A widget set to another fuel links stations the list may not have: its own copy then.
        return WidgetStations.load().first { $0.id == id }
    }

    func isCheapest(_ station: Station) -> Bool {
        guard let price = station.best(fuels)?.price, let cheapest = cheapestPrice else { return false }
        return price == cheapest
    }

    // MARK: - Lifecycle & Visibility

    func setIPhoneVisible(_ visible: Bool) {
        guard isIPhoneVisible != visible else { return }
        isIPhoneVisible = visible
        visibilityChanged()
    }

    func setCarPlayVisible(_ visible: Bool) {
        guard isCarPlayVisible != visible else { return }
        isCarPlayVisible = visible
        visibilityChanged()
    }

    func setCarPlayConnected(_ connected: Bool) {
        isCarPlayConnected = connected
    }

    private func visibilityChanged() {
        location.setCarPlayActive(isCarPlayVisible)
        if isAppVisible {
            resume()
        } else {
            location.stop()
            fetchTask?.cancel()
        }
    }

    // MARK: - Actions

    func start() {
        if Demo.isOn {
            if Demo.screen == .detail { selectedID = visible.first?.id }
            return
        }
        guard !started else { return }
        started = true
        Task { await StationRepository.shared.warmUp() }
        // Standing still, no location update comes: every minute, a new search once the list is 10 minutes old.
        // Suspended with the app in the background, so it only runs while the app or CarPlay is in use.
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.refreshIfOld()
            }
        }
    }

    private func refreshIfOld() {
        guard isAppVisible else { return }
        guard fetchTask == nil, let updatedAt, Date().timeIntervalSince(updatedAt) > Self.refetchInterval else { return }
        refresh()
    }

    /// Back to the foreground: a new search if the position changed or list is old.
    func resume() {
        guard !Demo.isOn else { return }
        guard isAppVisible else { return }
        location.start()
        if customLocation != nil {
            if let updatedAt, Date().timeIntervalSince(updatedAt) > Self.refetchInterval, fetchTask == nil { refresh() }
        } else if let current = location.location, isFresh(current) {
            if shouldReloadOnForeground(at: current), fetchTask == nil {
                refresh()
            }
        } else {
            needsReloadOnNextFix = true
        }
    }

    private func shouldReloadOnForeground(at location: CLLocation) -> Bool {
        guard let last = fetchedAt, let updatedAt, stations != nil else { return true }
        return last.distance(from: location) > 300 || Date().timeIntervalSince(updatedAt) > 5 * 60
    }

    func setFuels(_ newValue: [Fuel]) {
        guard !newValue.isEmpty, newValue != fuels else { return }
        fuels = newValue
        preferences.fuels = newValue
        stations = nil
        selectedID = nil
        fetchedAt = nil
        refresh(force: true)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setSort(_ newValue: StationOrder) {
        guard newValue != sort else { return }
        sort = newValue
        preferences.sort = newValue
        Task { await enrich() }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setNavigationApp(_ newValue: NavigationApp) {
        guard newValue != navigationApp else { return }
        navigationApp = newValue
        preferences.navigationApp = newValue
    }

    func setSearchRadius(_ newValue: Int) {
        guard Preferences.radiusChoices.contains(newValue), newValue != searchRadiusKm else { return }
        searchRadiusKm = newValue
        preferences.searchRadiusKm = newValue
        stations = nil
        selectedID = nil
        fetchedAt = nil
        refresh(force: true)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func toggleFuel(_ fuel: Fuel) {
        let next = fuels.contains(fuel) ? fuels.filter { $0 != fuel } : Fuel.allCases.filter { fuels.contains($0) || $0 == fuel }
        setFuels(next)
    }

    /// Searches stations around a selected town / coordinates.
    func searchTown(name: String, coordinate: CLLocationCoordinate2D) {
        isSearching = false
        customTownName = name
        let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        customLocation = targetLocation
        filterText = ""
        stations = nil
        selectedID = nil
        fetchedAt = nil
        fetchTask?.cancel()
        let fuels = fuels
        let task = Task { await self.fetch(around: targetLocation, fuels: fuels) }
        fetchTask = task
    }

    /// Resets search to the user's current GPS location.
    func resetToCurrentLocation() {
        isSearching = false
        guard customTownName != nil || customLocation != nil else { return }
        customTownName = nil
        customLocation = nil
        filterText = ""
        stations = nil
        selectedID = nil
        fetchedAt = nil
        refresh(force: true)
    }

    /// `carburants://station/<id>`, from the widget.
    func open(_ url: URL) {
        guard url.scheme == "carburants", url.host() == "station", let id = Int64(url.lastPathComponent) else { return }
        selectedID = id
    }

    /// Starts a search around the active position (custom town or GPS); await the task for pull to refresh.
    @discardableResult
    func refresh(force: Bool = false) -> Task<Void, Never>? {
        guard isAppVisible || force else { return nil }
        let target = customLocation ?? location.location
        guard let target else { return nil }
        fetchTask?.cancel()
        let fuels = fuels
        let task = Task { await self.fetch(around: target, fuels: fuels) }
        fetchTask = task
        return task
    }

}

// MARK: - Loading

extension StationsModel {
    private func locationChanged(_ location: CLLocation) {
        // Only track and refresh if UI is currently visible
        guard isAppVisible else { return }
        guard customLocation == nil else { return }
        guard isFresh(location) else { return }
        updateDistances(to: location)
        if fetchTask != nil {
            // A search is running from an earlier position: start again when this one is far from it.
            if let from = fetchedAt, location.distance(from: from) > Self.refetchMeters { refresh() }
        } else if needsReloadOnNextFix {
            needsReloadOnNextFix = false
            if shouldReloadOnForeground(at: location) {
                refresh()
            }
        } else if isStale(location) {
            refresh()
        }
    }

    private func updateDistances(to location: CLLocation) {
        guard let currentStations = stations, !currentStations.isEmpty else { return }
        let coord = location.coordinate
        stations = currentStations.map { station in
            var station = station
            station.distanceKm = Geo.distanceKm(coord.latitude, coord.longitude, station.latitude, station.longitude)
            return station
        }
    }

    private func isFresh(_ location: CLLocation) -> Bool {
        -location.timestamp.timeIntervalSinceNow < Self.maxFixAge
    }

    private func isStale(_ location: CLLocation) -> Bool {
        guard let last = fetchedAt, let updatedAt, stations != nil else { return true }
        return last.distance(from: location) > Self.refetchMeters || Date().timeIntervalSince(updatedAt) > Self.refetchInterval
    }

    private func fetch(around location: CLLocation, fuels: [Fuel]) async {
        phase = .loading
        fetchedAt = location
        let coordinate = location.coordinate
        do {
            let result = try await StationRepository.shared.nearby(
                latitude: coordinate.latitude, longitude: coordinate.longitude, fuels: fuels
            )
            guard !Task.isCancelled else { return }
            stations = result.stations
            listCoordinate = coordinate
            radiusKm = result.radiusKm
            updatedAt = .now
            phase = .idle
            fetchTask = nil
            // Only update widget/lastLocation if searching from actual GPS location
            if customLocation == nil {
                preferences.lastLocation = .init(
                    latitude: (coordinate.latitude * 1000).rounded() / 1000,
                    longitude: (coordinate.longitude * 1000).rounded() / 1000,
                    date: .now
                )
                WidgetCenter.shared.reloadAllTimelines()
            }
            saveSnapshot(at: coordinate)
            await enrich()
        } catch {
            guard !Task.isCancelled else { return }
            fetchTask = nil
            fetchedAt = nil // Try again on the next position.
            phase = .failed("Impossible de récupérer les prix. Vérifiez la connexion.")
        }
    }

    /// Brands, names and logos of the first stations, then one redraw. The lookups can take long: by then a newer
    /// search may have replaced the list, so only names, brands and logos are copied, never prices or distances.
    private func enrich() async {
        let shown = Array(visible.prefix(20))
        guard !shown.isEmpty else { return }
        if let updated = await StationRepository.shared.enrich(shown) {
            stations = stations?.map { station in
                guard let found = updated[station.id] else { return station }
                var station = station
                station.name = found.name
                station.brand = found.brand
                station.logoURL = found.logoURL
                return station
            }
            if let listCoordinate { saveSnapshot(at: listCoordinate) }
        }
        await LogoStore.shared.preload(Array(visible.prefix(20)))
    }

    private func saveSnapshot(at coordinate: CLLocationCoordinate2D) {
        guard let stations else { return }
        let snapshot = Snapshot(
            date: updatedAt ?? .now, latitude: coordinate.latitude, longitude: coordinate.longitude,
            fuels: fuels, radiusKm: radiusKm, stations: stations
        )
        Task.detached(priority: .background) {
            snapshot.save()
        }
    }
}
