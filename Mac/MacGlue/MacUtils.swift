import Foundation

@objc(MacUtils)
protocol MacUtils: NSObjectProtocol {
    init()

    func openClicMiniApp()
    func runningUpdate(handler: @escaping (Bool) -> Void)
    func setupRunningAppsObserver()
    func stopRunningAppObserver()
    
    // MARK: Not used
    func disableSecureEventInput()
    func isSecureEventInputEnabled() -> Bool
    func isControlKeyPressed() -> Bool
}
