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
}
