import SwiftUI
import UIKit

/// Puts the paywall up over whatever is on screen: Play On, the full-screen
/// player, a sheet, any tab. The routers' full-screen covers hang off a
/// tab's screen, which can't present while the player or a sheet is up, nor
/// from a tab that isn't showing, so a gate tapped there opened nothing.
/// Presented here, a sheet that asked stays under it, and closing the
/// paywall goes back to it.
@MainActor
enum PaywallPresenter {
    static func present() {
        guard let top = topController() else { return }
        // One at a time.
        if top is PaywallHost { return }
        // A sheet on its way down can't be presented over: wait for it.
        if let coordinator = top.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in present() }
            return
        }
        let host = PaywallHost(rootView: AnyView(CuePaywall().withEnvironments()))
        host.modalPresentationStyle = .fullScreen
        top.present(host, animated: true)
    }

    /// The controller presented last in the active window, past any on its
    /// way down.
    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = (scene?.keyWindow ?? scene?.windows.first)?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

private final class PaywallHost: UIHostingController<AnyView> {}
