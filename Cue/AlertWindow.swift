import SonosKit
import SwiftUI
#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit

/// The alert's own window, one per scene, above everything the app shows:
/// sheets, full-screen covers, popovers, navigation and tab bars. The
/// capsule is always just under the status bar, whatever's on screen, and
/// no screen needs a host of its own (`withAlert()` is for the Mac and
/// visionOS).
///
/// The window is hidden while there's no alert, so the app's own screens
/// keep the status bar, and it takes touches only inside the capsule.
@MainActor
final class AlertWindowController {
    private static var controllers: [ObjectIdentifier: AlertWindowController] = [:]

    /// Puts one over `scene`, once.
    static func install(over scene: UIWindowScene) {
        controllers = controllers.filter { $0.value.scene != nil }
        let key = ObjectIdentifier(scene)
        guard controllers[key] == nil else { return }
        controllers[key] = AlertWindowController(scene: scene)
    }

    private weak var scene: UIWindowScene?
    private let window: AlertWindow
    private var hideTask: Task<Void, Never>?

    private init(scene: UIWindowScene) {
        self.scene = scene
        let window = AlertWindow(windowScene: scene)
        self.window = window
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear

        let root = AlertHostingController(rootView: AlertWindowRoot { [weak window] frame in
            window?.capsuleFrame = frame
        })
        root.view.backgroundColor = .clear
        root.appWindow = { [weak self] in self?.appWindow }
        window.rootViewController = root
        // Laid out once now, so even the first alert comes in animated,
        // into a view that's already there.
        window.isHidden = false
        window.layoutIfNeeded()
        window.isHidden = true

        AlertService.shared.addPresenter { [weak self] isComing in
            if isComing {
                self?.show()
            } else {
                self?.hideAfterExit()
            }
        }
        if AlertService.shared.alert.isShowing {
            show()
        }
    }

    /// The scene's own window, under this one.
    private var appWindow: UIWindow? {
        scene?.keyWindow ?? scene?.windows.first { $0 !== window }
    }

    /// Up before the alert comes in, so its entrance is drawn. Never key,
    /// so the keyboard and focus stay where they are.
    private func show() {
        hideTask?.cancel()
        hideTask = nil
        guard window.isHidden else { return }
        if let appWindow {
            // Settings ▸ Appearance sets the app's windows, maybe before
            // this one was there.
            window.overrideUserInterfaceStyle = appWindow.overrideUserInterfaceStyle
        }
        window.isHidden = false
        window.rootViewController?.setNeedsStatusBarAppearanceUpdate()
    }

    /// Down once the capsule has faded (`AlertView`'s exit takes 0.3 s),
    /// handing the status bar back to the app.
    private func hideAfterExit() {
        window.capsuleFrame = .zero
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled, !AlertService.shared.alert.isShowing else { return }
            window.isHidden = true
            appWindow?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        }
    }
}

/// Takes touches only inside the capsule; everywhere else they go through
/// to the app. (Since iOS 18 a SwiftUI hosting view answers for its whole
/// area, so passing through on the background alone doesn't work.)
final class AlertWindow: UIWindow {
    var capsuleFrame: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard capsuleFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// While the window is up it has the status bar, so it looks the way the
/// app's screen under it wants.
private final class AlertHostingController: UIHostingController<AlertWindowRoot> {
    var appWindow: () -> UIWindow? = { nil }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        statusBarController?.preferredStatusBarStyle ?? .default
    }

    /// What decides the status bar in the app's window: the top full-screen
    /// presentation (a sheet leaves it to the screen under it), then down
    /// the children it hands the style to.
    private var statusBarController: UIViewController? {
        var controller = appWindow()?.rootViewController
        while let presented = controller?.presentedViewController,
              presented.modalPresentationCapturesStatusBarAppearance
                || [.fullScreen, .overFullScreen].contains(presented.modalPresentationStyle) {
            controller = presented
        }
        for _ in 0..<8 {
            guard let child = controller?.childForStatusBarStyle, child !== controller else { break }
            controller = child
        }
        return controller
    }
}

private struct AlertWindowRoot: View {
    let onCapsuleFrame: (CGRect) -> Void

    var body: some View {
        AlertView(inWindow: true, onCapsuleFrame: onCapsuleFrame)
            .environment(AlertService.shared)
            .environment(SonosService.shared)
    }
}

/// Installs the window over the scene this view is in, once it's in one.
private struct AlertWindowInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene {
                AlertWindowController.install(over: scene)
            }
        }
    }
}
#endif

extension View {
    /// Gives this view's scene the alert's own window (iOS). On the Mac and
    /// visionOS the screens host the alert themselves (`withAlert()`).
    @ViewBuilder
    func alertWindow() -> some View {
#if os(iOS) && !targetEnvironment(macCatalyst)
        background {
            AlertWindowInstaller()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
#else
        self
#endif
    }
}
