#if os(iOS) && !targetEnvironment(macCatalyst)
import CarPlay
import UIKit

/// The car's screen. CarPlay connects this scene next to the app's window —
/// or on its own, with the phone locked in a pocket, in which case no
/// window and none of `CueApp`'s `onAppear` work ever runs. Everything it
/// shows is `CarPlayInterface`'s; this only starts and stops it.
///
/// Declared in Info.plist's scene manifest, which is how CarPlay knows Cue
/// has a car screen, and needs the `com.apple.developer.carplay-audio`
/// entitlement in `Cue-iOS.entitlements`.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interface: CarPlayInterface?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        CarConnection.sceneConnected(true)
        let interface = CarPlayInterface(interfaceController: interfaceController)
        self.interface = interface
        interface.start()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        interface?.stop()
        interface = nil
        CarConnection.sceneConnected(false)
    }

    /// The configuration for a scene CarPlay is connecting, or nil for any
    /// other role. `AppDelegate` asks this first: it hands every scene it
    /// configures a window delegate, which can't drive CarPlay's templates.
    /// The name matches the Info.plist entry.
    static func configuration(for session: UISceneSession) -> UISceneConfiguration? {
        guard session.role == .carTemplateApplication else { return nil }
        let configuration = UISceneConfiguration(name: "CarPlay", sessionRole: session.role)
        configuration.sceneClass = CPTemplateApplicationScene.self
        configuration.delegateClass = CarPlaySceneDelegate.self
        return configuration
    }
}
#endif
