import CarPlay

/// CarPlay scene (Fueling category: com.apple.developer.carplay-fueling). Declared in Info.plist under
/// CPTemplateApplicationSceneSessionRoleApplication; the iPhone window stays a SwiftUI WindowGroup.
// swiftlint:disable:next unused_declaration - instantiated by UIKit from Info.plist
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var controller: CarPlayController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        let controller = CarPlayController(interface: interfaceController, scene: templateApplicationScene)
        self.controller = controller
        controller.start()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        controller = nil
    }
}
