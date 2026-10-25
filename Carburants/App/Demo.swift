import Foundation

/// Screenshot mode, for scripts/screenshots.sh only: launched with `-demo YES`, the app shows the sample stations
/// around Rennes instead of searching, `-demoScreen list|detail|fuels` opens that screen and
/// `-demoCarPlay map|list|detail|fuels` that CarPlay screen.
enum Demo {
    enum Screen: String {
        case list, detail, fuels
    }

    enum CarPlayScreen: String {
        /// The map, the list, the cheapest station's details, the fuel picker.
        case map, list, detail, fuels
    }

    static let isOn = UserDefaults.standard.bool(forKey: "demo")
    static let screen = UserDefaults.standard.string(forKey: "demoScreen").flatMap(Screen.init(rawValue:)) ?? .list
    static let carPlay = UserDefaults.standard.string(forKey: "demoCarPlay").flatMap(CarPlayScreen.init(rawValue:)) ?? .map
}
