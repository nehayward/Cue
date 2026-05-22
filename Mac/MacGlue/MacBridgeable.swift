import Foundation

/// Bundle entry point. ClicMini launch + running-process observation. The
/// dock-menu surface lives separately behind `DockMenuRenderable` — get to it
/// via `dockMenu`.
@objc(MacBridgeable)
protocol MacBridgeable: NSObjectProtocol {
    init()

    func openClicMiniApp()
    func openClicMiniApp() async throws

    func runningUpdate(handler: @escaping (Bool) -> Void)
    func setupRunningAppsObserver()
    func stopRunningAppObserver()

    /// Dock menu renderer. Lazily created on first access; safe to call
    /// repeatedly — returns the same instance.
    var dockMenu: DockMenuRenderable { get }
}
