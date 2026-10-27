#if os(iOS)
import UIKit

@MainActor
enum SpaceControlOrientation {
    private(set) static var controlling = false
    static var supported: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : controlling ? .allButUpsideDown : .portrait
    }
    static func setControlling(_ value: Bool) {
        controlling = value
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes where scene.activationState == .foregroundActive {
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: supported)) { _ in }
        }
    }
}
#endif
