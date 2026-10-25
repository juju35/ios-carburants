import CarburantsKit
// swiftlint:disable:next unused_import - also reached through another import, kept explicit for Swift 6
import CoreLocation
import Observation
import WidgetKit

/// Stations around the phone, shared by every window (iPhone, iPhone Duo in Split View, iPad) and CarPlay.
@MainActor
@Observable
final class StationsModel {
    static let shared = StationsModel()

    enum Phase: Equatable {
        case idle, loading
        case failed(String)
    }

    let location = LocationProvider()

    private(set) var fuels: [Fuel]
    private(set) var sort: StationOrder
    /// nil until a first search returns.
    private(set) var stations: [Station]?
    private(set) var radiusKm = StationRepository.radiusKm
    private(set) var phase: Phase = .idle
    private(set) var updatedAt: Date?
    /// The station shown on the map and in the detail.
    var selectedID: Station.ID?
    /// The fuel picker, opened from the list's toolbar (and by the demo mode).
    var showsFuelPicker = false

    @ObservationIgnored private let preferences = Preferences.shared
    @ObservationIgnored private var fetchedAt: CLLocation?
    /// Where the stations on screen were searched (the snapshot is saved under it).
    @ObservationIgnored private var listCoordinate: CLLocationCoordinate2D?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    // New search after 2 km or 10 minutes (the feed is refreshed every 10 minutes).
    private static let refetchMeters: CLLocationDistance = 2_000
    private static let refetchInterval: TimeInterval = 10 * 60
    // CoreLocation first hands over its last known fix, possibly hours old: not a place to search around.
    private static let maxFixAge: TimeInterval = 60

    private init() {
        if Demo.isOn {
            // Opening statuses at 9:41, the status bar's time, whenever the screenshots are taken.
            Opening.clock = { Opening.nineFortyOne }
            fuels = [.gazole, .e10]
            sort = .price
            stations = Station.samples
            updatedAt = .now.addingTimeInterval(-4 * 60)
            return
        }
        fuels = preferences.fuels
        sort = preferences.sort
        // Last list for an instant start, when recent and for the same fuels; distances refresh with the next search.
        if let snapshot = Snapshot.load(), snapshot.fuels == preferences.fuels, Date().timeIntervalSince(snapshot.date) < 30 * 60 {
            stations = snapshot.stations
            radiusKm = snapshot.radiusKm
            updatedAt = snapshot.date
            listCoordinate = CLLocationCoordinate2D(latitude: snapshot.latitude, longitude: snapshot.longitude)
        }
        location.onUpdate = { [weak self] location in self?.locationChanged(location) }
    }

    // MARK: - Derived

    var visible: [Station] { StationSort.sorted(stations ?? [], by: sort, fuels: fuels) }

    var cheapestPrice: Double? { visible.compactMap { $0.best(fuels)?.price }.min() }

    func station(_ id: Station.ID?) -> Station? {
        guard let id else { return nil }
        // A widget set to another fuel links stations the list may not have: its own copy then.
        return stations?.first { $0.id == id } ?? WidgetStations.load().first { $0.id == id }
    }

    func isCheapest(_ station: Station) -> Bool {
        guard let price = station.best(fuels)?.price, let cheapest = cheapestPrice else { return false }
        return price == cheapest
    }

    // MARK: - Actions

    func start() {
        if Demo.isOn {
            if Demo.screen == .detail { selectedID = visible.first?.id }
            return
        }
        location.start()
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
        guard fetchTask == nil, let updatedAt, Date().timeIntervalSince(updatedAt) > Self.refetchInterval else { return }
        refresh()
    }

    /// Back to the foreground: a new search if the list is old.
    func resume() {
        guard !Demo.isOn else { return }
        location.start()
        if let current = location.location, isFresh(current), isStale(current), fetchTask == nil { refresh() }
    }

    func setFuels(_ newValue: [Fuel]) {
        guard !newValue.isEmpty, newValue != fuels else { return }
        fuels = newValue
        preferences.fuels = newValue
        stations = nil
        selectedID = nil
        fetchedAt = nil
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func setSort(_ newValue: StationOrder) {
        guard newValue != sort else { return }
        sort = newValue
        preferences.sort = newValue
        Task { await enrich() }
    }

    func toggleFuel(_ fuel: Fuel) {
        let next = fuels.contains(fuel) ? fuels.filter { $0 != fuel } : Fuel.allCases.filter { fuels.contains($0) || $0 == fuel }
        setFuels(next)
    }

    /// `carburants://station/<id>`, from the widget.
    func open(_ url: URL) {
        guard url.scheme == "carburants", url.host() == "station", let id = Int64(url.lastPathComponent) else { return }
        selectedID = id
    }

    /// Starts a search around the current position; await the task for pull to refresh.
    @discardableResult
    func refresh() -> Task<Void, Never>? {
        guard let current = location.location else { return nil }
        fetchTask?.cancel()
        let fuels = fuels
        let task = Task { await self.fetch(around: current, fuels: fuels) }
        fetchTask = task
        return task
    }

    // MARK: - Loading

    private func locationChanged(_ location: CLLocation) {
        guard isFresh(location) else { return }
        if fetchTask != nil {
            // A search is running from an earlier position: start again when this one is far from it.
            if let from = fetchedAt, location.distance(from: from) > Self.refetchMeters { refresh() }
        } else if isStale(location) {
            refresh()
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
            preferences.lastLocation = .init(latitude: coordinate.latitude, longitude: coordinate.longitude, date: .now)
            saveSnapshot(at: coordinate)
            WidgetCenter.shared.reloadAllTimelines()
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
        Snapshot(
            date: updatedAt ?? .now, latitude: coordinate.latitude, longitude: coordinate.longitude,
            fuels: fuels, radiusKm: radiusKm, stations: stations
        ).save()
    }
}
