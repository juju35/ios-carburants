import CarPlay

/// CarPlay scene (Fueling category: com.apple.developer.carplay-fueling). Declared in Info.plist under
/// CPTemplateApplicationSceneSessionRoleApplication; the iPhone window stays a SwiftUI WindowGroup.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate { // swiftlint:disable:this unused_declaration
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
