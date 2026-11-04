#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// The paywall in a window of its own on the Mac, whoever asks for it
/// (`PaywallPresenter`, a router's `.paywall` cover): presented where it was
/// asked for, it took a Settings pane's place under its toolbar, or the whole of
/// the main window.
///
/// A SwiftUI scene of its own (`CueApp`), which `CueSceneDelegate` sets up rather
/// than as the main window, as it does Settings: a session is this window's when
/// it connects just after `open` asked for one. One macOS brings back at launch
/// goes again, as nothing asked for it.
@MainActor @Observable
final class PaywallWindow {
    static let shared = PaywallWindow()
    static let sceneID = "paywall"

    private static let sessionMark = "dance.cue.paywall"

    /// The gate that brought it up, for the paywall to open on.
    private(set) var reason: PaywallReason?

    @ObservationIgnored private weak var scene: UIWindowScene?
    @ObservationIgnored private var askedAt: Date?

    private init() {}

    /// Shows the paywall, or brings it forward where it's open already.
    func open(_ reason: PaywallReason? = nil) {
        self.reason = reason
        if let scene {
            UIApplication.shared.requestSceneSessionActivation(scene.session, userActivity: nil, options: nil)
            return
        }
        askedAt = .now
        SettingsWindow.shared.openWindow?(id: Self.sceneID)
    }

    func close() {
        guard let scene else { return }
        UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil)
    }

    /// Whether the session connecting is this window's: marked, or asked for by
    /// `open` a moment ago.
    func claims(_ session: UISceneSession) -> Bool {
        if session.userInfo?[Self.sessionMark] as? Bool == true { return true }
        guard let askedAt else { return false }
        return askedAt.timeIntervalSinceNow > -3
    }

    /// Sets the window up as it connects, in place of the main window's setup.
    func connect(_ scene: UIWindowScene) {
        guard askedAt != nil else {
            UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil)
            return
        }
        askedAt = nil
        self.scene = scene
        SettingsWindow.markNotMain(scene.session)
        var info = scene.session.userInfo ?? [:]
        info[Self.sessionMark] = true
        scene.session.userInfo = info

        scene.title = "Cue Super"
        scene.titlebar?.titleVisibility = .hidden
        scene.titlebar?.toolbar = nil
        scene.sizeRestrictions?.allowsFullScreen = false
        fit(scene)
    }

    func disconnect(_ scene: UIScene) {
        guard scene === self.scene else { return }
        self.scene = nil
        reason = nil
    }

    /// As wide as Settings and tall enough for the paywall with no reason to
    /// scroll, over the main window, neither left to drag. A point between the
    /// least and most size, as `SettingsWindow.setFrame` says why.
    private func fit(_ scene: UIWindowScene) {
        let scale = LargeWindowStyle.scale(AppState.shared.interfaceSize.typeSize)
        let width = (Self.width * scale).rounded()
        let height = min(Self.height * scale, scene.screen.bounds.height * 0.9).rounded()
        if let restrictions = scene.sizeRestrictions {
            restrictions.minimumSize = .zero
            restrictions.maximumSize = CGSize(width: width + 1, height: height + 1)
            restrictions.minimumSize = CGSize(width: width - 1, height: height - 1)
        }

        // The system's frame is in the Mac's points, the scene's in the iPad's.
        let points = scene.effectiveGeometry.coordinateSpace.bounds.size
        var frame = scene.effectiveGeometry.systemFrame
        let ratio = points.width > 0 && frame.width > 0 ? frame.width / points.width : 0.77
        frame.size = CGSize(width: width * ratio, height: height * ratio)
        if let main = SettingsWindow.mainWindowFrame(besides: scene) {
            frame.origin = CGPoint(x: main.midX - frame.width / 2, y: main.midY - frame.height / 2)
        }
        scene.requestGeometryUpdate(.Mac(systemFrame: frame))
    }

    /// In the iPad's points, at the default scale's 1.
    private static let width: CGFloat = 600
    private static let height: CGFloat = 790
}

/// What the paywall's window shows.
struct PaywallWindowScreen: View {
    @State private var window = PaywallWindow.shared
    @State private var appState = AppState.shared

    var body: some View {
        CuePaywall(reason: window.reason, onClose: { PaywallWindow.shared.close() })
            .withEnvironments()
            .withPadLayout()
            .interfaceSize(appState.interfaceSize)
            // Links go to the main window, which handles them.
            .handlesExternalEvents(preferring: [], allowing: [])
    }
}
#endif
