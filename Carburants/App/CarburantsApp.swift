import SwiftUI

@main
struct CarburantsApp: App {
    @State private var model = StationsModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        // One window per scene: Split View on iPhone Duo and iPad opens more than one, all on the same model.
        WindowGroup {
            ContentView(model: model)
                .onOpenURL { model.open($0) }
                .onAppear { model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.resume() }
                }
        }
    }
}
