import Foundation

/// Bundle entry point. CueMini launch + running-process observation. The
/// dock-menu surface lives separately behind `DockMenuRenderable` — get to it
/// via `dockMenu`.
@objc(MacBridgeable)
protocol MacBridgeable: NSObjectProtocol {
    init()

    func openCueMiniApp()
    func openCueMiniApp() async throws

    func runningUpdate(handler: @escaping (Bool) -> Void)
    /// Whether Cue Mini is running now, asked of the system rather than
    /// `isRunning`, which only moves while the observer is set up.
    var isCueMiniRunning: Bool { get }
    /// Debug builds, as one launches: leaves one development copy of Cue
    /// running. Two fight over the Sonos event port and Cue Mini's link.
    func keepOneDevelopmentCopy()
    func setupRunningAppsObserver()
    func stopRunningAppObserver()

    /// Dock menu renderer. Lazily created on first access; safe to call
    /// repeatedly — returns the same instance.
    var dockMenu: DockMenuRenderable { get }

    /// The system dictionary's entry for `term` as plain text, or nil when
    /// no dictionary has one. UIKit's dictionary page only opens Dictionary
    /// on the Mac, so Cue lays this out itself (`DictionaryDefinitionView`).
    func definition(of term: String) -> String?

    /// Posts a distributed notification, delivered at once even to an app
    /// in the background. A sandboxed app can send a string `object` but no
    /// user info. Catalyst has no `DistributedNotificationCenter` of its
    /// own; this is how Cue talks to Cue Mini (`CueMiniLink`).
    func postDistributedNotification(named name: String, object: String?)

    /// Calls `handler` on the main thread with the object of each
    /// distributed notification named `name`, delivered even while Cue is
    /// in the background. A second call for the same name replaces the
    /// handler.
    func observeDistributedNotification(named name: String, handler: @escaping (String?) -> Void)

    /// The standard About panel (Cue ▸ About Cue) with `credits` under the
    /// version, small and centred, each phrase in `links` (its URL as a
    /// string) a link in it.
    func showAboutPanel(credits: String, links: [String: String])

    /// Puts macOS's sidebar material (the desktop behind the window showing
    /// through, blurred, as in Music's sidebar) under the whole of each
    /// window titled `title`, beneath Cue's own content, so what Cue leaves
    /// clear shows it. Once a window; again is a no-op.
    func installSidebarMaterial(inWindowsTitled title: String)

    /// Makes the close button of each window titled `title` hide Cue rather
    /// than close the window, as a music app's does: Cue plays on, and a
    /// click on its Dock icon brings the same window back with everything
    /// where it was. A closed window came back built anew, every page
    /// loading again. Again is harmless.
    func hideOnClose(windowsTitled title: String)

    /// Hides Cue, as Cue ▸ Hide Cue does: what the main window's close
    /// button and ⌘W do (`hideOnClose`).
    func hideApp()
}
