import MapKit
import Observation

/// Suggestion item for French towns/cities.
struct TownSuggestion: Hashable, Identifiable, Sendable {
    var id: String { "\(title)_\(subtitle)" }
    let title: String
    let subtitle: String
}

/// Suggests French towns/cities as the user types using MKLocalSearchCompleter.
@MainActor
@Observable
final class TownSearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    var suggestions: [TownSuggestion] = []
    var isSearching = false

    /// France bounding region (from western Brittany/Ouessant to Corsica and Alsace).
    private static let franceRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 46.5, longitude: 2.2),
        span: MKCoordinateSpan(latitudeDelta: 12.0, longitudeDelta: 17.0)
    )

    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                completer.cancel()
                suggestions = []
                isSearching = false
            } else {
                isSearching = true
                completer.queryFragment = trimmed
            }
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = Self.franceRegion
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results
            .filter { completion in
                guard !completion.title.isEmpty, completion.title.lowercased() != "france" else { return false }
                let sub = completion.subtitle.lowercased()
                return sub.contains("france") || sub.isEmpty
            }
            .prefix(5)
            .map { TownSuggestion(title: $0.title, subtitle: $0.subtitle) }
        Task { @MainActor in
            self.suggestions = Array(items)
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
            self.isSearching = false
        }
    }

    static func resolve(suggestion: TownSuggestion) async -> (name: String, coordinate: CLLocationCoordinate2D)? {
        let fullQuery = suggestion.subtitle.isEmpty ? "\(suggestion.title), France" : "\(suggestion.title), \(suggestion.subtitle)"
        return await resolve(query: fullQuery)
    }

    static func resolve(query: String) async -> (name: String, coordinate: CLLocationCoordinate2D)? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.lowercased().contains("france") ? query : "\(query), France"
        request.region = franceRegion
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(), let item = response.mapItems.first else {
            return nil
        }
        let name = item.name ?? query
        let coordinate: CLLocationCoordinate2D
        if #available(iOS 26.0, *) {
            coordinate = item.location.coordinate
        } else {
            coordinate = item.placemark.coordinate
        }
        return (name: name, coordinate: coordinate)
    }
}
