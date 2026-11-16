import UIKit
import SwiftUI
import CarPlay

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var carWindow: CPWindow?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.carWindow = window
        let hostingController = UIHostingController(rootView: SplitScreenWorkspaceView())
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        AppStateManager.shared.isCarPlayConnected = true
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        self.carWindow = nil
        AppStateManager.shared.isCarPlayConnected = false
    }
}