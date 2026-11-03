#if targetEnvironment(macCatalyst)
import UIKit

/// macOS's own sidebar material behind the whole main window
/// (`MacBridgeable.installSidebarMaterial`), which the shell's clear
/// sidebar and queue show, the desktop coming through them as through
/// Music's. A Catalyst app has no other way to draw it but a split view's
/// sidebar column, and a split, which narrows its content column at once,
/// made the page jump and left a black bar as the queue came and went.
/// The window and its root are made clear first, so the material shows
/// through what Cue leaves clear; the page draws its own background.
@MainActor
enum WindowMaterial {
    static func install() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
        where !SettingsWindow.isMarked(scene.session) {
            for window in scene.windows {
                window.backgroundColor = .clear
                window.rootViewController?.view.backgroundColor = .clear
            }
        }
        // The window's AppKit side may not be up as the shell first
        // appears; a window that has it already is left as it is.
        Task {
            for _ in 0..<5 {
                MenuAppLaunchAtLoginManager.shared.bridge?.installSidebarMaterial(inWindowsTitled: "Cue")
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }
}
#endif
