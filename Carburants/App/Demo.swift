import Foundation

/// Screenshot mode, for scripts/screenshots.sh only: launched with `-demo YES`, the app shows the sample stations
/// around Rennes instead of searching, and `-demoScreen list|detail|fuels` opens that screen.
enum Demo {
    enum Screen: String {
        case list, detail, fuels
    }

    static let isOn = UserDefaults.standard.bool(forKey: "demo")
    static let screen = UserDefaults.standard.string(forKey: "demoScreen").flatMap(Screen.init(rawValue:)) ?? .list
}
