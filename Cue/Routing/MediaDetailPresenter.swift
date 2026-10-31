import SonosKit
import SwiftUI
import UIKit

/// Opens a playlist's, album's or collection's page over whatever is on
/// screen, for the toasts that say something went into one ("Added to …",
/// "Created Playlist"), which open it when tapped. They used to set
/// `Router.main`'s sheet, which nothing in the window hosts (each tab
/// presents from a router of its own): the tap opened nothing, and the value
/// it left behind drew `addDismiss`'s close button on screens that weren't
/// presented at all. Presented from the top controller instead, as
/// `PaywallPresenter` does, so it opens over the player and sheets too.
@MainActor
enum MediaDetailPresenter {
    static func present(_ content: PlayableContent) {
        guard let top = TopViewController.current else { return }
        // A sheet on its way down can't be presented over: wait for it.
        if let coordinator = top.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in present(content) }
            return
        }
        let host = PresentedPageHost(rootView: AnyView(PresentedMediaDetail(content: content).withEnvironments()))
        // The `.page` sizing the router's sheets ask for.
        host.modalPresentationStyle = .pageSheet
        top.present(host, animated: true)
    }

    /// Takes down the pages presented here, and anything over them, for a
    /// link that opens something of its own.
    static func dismissPresented() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var controller = (scene?.keyWindow ?? scene?.windows.first)?.rootViewController
        while let presented = controller?.presentedViewController {
            if presented is PresentedPageHost, !presented.isBeingDismissed {
                presented.presentingViewController?.dismiss(animated: false)
                return
            }
            controller = presented
        }
    }
}

/// A page `MediaDetailPresenter` put up, to tell it from other presentations.
private final class PresentedPageHost: UIHostingController<AnyView> {}

/// The controller presented last in the active window, past any on its way
/// down: where something presented over whatever is on screen goes.
@MainActor
enum TopViewController {
    static var current: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = (scene?.keyWindow ?? scene?.windows.first)?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

/// The page as the router's `.mediaDetail` sheet shows it
/// (`withSheetDestinations`), in a navigation stack of its own, with a close
/// button: there's no router sheet behind it for `addDismiss` to find.
private struct PresentedMediaDetail: View {
    @Environment(\.dismiss) private var dismiss
    @State private var router = Router()
    @State private var selectedGroupService = SelectedGroupService(group: nil)

    let content: PlayableContent

    var body: some View {
        NavigationStack(path: $router.path) {
            MediaDetailDestination(content: content)
                .navigationBarTitleDisplayMode(.inline)
                .withAppRouter()
                .addDismiss(override: true) {
                    dismiss()
                }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(router)
        .environment(selectedGroupService)
        .customizeWindowSizeForMacOS15()
        .withAlert()
    }
}
