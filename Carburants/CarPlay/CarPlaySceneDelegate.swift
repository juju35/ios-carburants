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
        StationsModel.shared.setCarPlayConnected(true)
        controller.start()
        if templateApplicationScene.activationState == .foregroundActive {
            StationsModel.shared.setCarPlayVisible(true)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        controller = nil
        StationsModel.shared.setCarPlayConnected(false)
        StationsModel.shared.setCarPlayVisible(false)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        StationsModel.shared.setCarPlayVisible(true)
        controller?.sceneDidBecomeActive()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        StationsModel.shared.setCarPlayVisible(false)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        StationsModel.shared.setCarPlayVisible(false)
    }
}
