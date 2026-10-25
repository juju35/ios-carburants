import CoreLocation
import Observation

/// The phone's position while the app (or its CarPlay scene) is in use.
@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    private(set) var authorization: CLAuthorizationStatus
    /// Approximate location only (the user turned off "Precise Location"): distances are off by up to a few km.
    private(set) var isApproximate: Bool
    /// CoreLocation could not find the position (no signal, airplane mode…); cleared by the next fix.
    private(set) var failed = false

    @ObservationIgnored var onUpdate: ((CLLocation) -> Void)?
    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorization = manager.authorizationStatus
        isApproximate = manager.accuracyAuthorization == .reducedAccuracy
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        manager.activityType = .automotiveNavigation
    }

    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func start() {
        switch authorization {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: break
        }
    }

    func requestPermission() { manager.requestWhenInUseAuthorization() }

    /// Asks for the precise location this time, with the reason in Info.plist (NSLocationTemporaryUsageDescriptionDictionary).
    func requestPrecise() {
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "NearbyStations")
    }

    /// Tries again after a failure.
    func retry() {
        failed = false
        manager.stopUpdatingLocation()
        start()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let approximate = manager.accuracyAuthorization == .reducedAccuracy
        Task { @MainActor in
            self.authorization = status
            self.isApproximate = approximate
            if self.isAuthorized { self.manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.location = last
            self.failed = false
            self.onUpdate?(last)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A denial shows through the authorization; locationUnknown is temporary, CoreLocation keeps trying.
        let code = (error as? CLError)?.code
        guard code != .denied, code != .locationUnknown else { return }
        Task { @MainActor in self.failed = true }
    }
}
