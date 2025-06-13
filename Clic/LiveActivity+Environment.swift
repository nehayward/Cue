import SwiftUI

protocol LiveActivityManageable {
    func refresh() async
    func createActivity()
    func createActivity(id: String) async
    func stop(id: String) async
    func toggle(id: String) async
    func reset() async
    
    func isActivityDisabled(id: String) -> Bool
    func disableActivity(id: String)
    func enableActivity(id: String)
    func toggleActivityEnabled(id: String)
}

struct LiveActivityManagerKey: EnvironmentKey {
    // you can also set the real user service as the default value
    #if os(iOS) && canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    static let defaultValue: any LiveActivityManageable = LiveActivityManager()
    #else
    static let defaultValue: any LiveActivityManageable = LiveActivityManagerMock()
    #endif
}

extension EnvironmentValues {
    var liveActivityManager: any LiveActivityManageable {
        get { self[LiveActivityManagerKey.self] }
        set { self[LiveActivityManagerKey.self] = newValue }
    }
}

final class LiveActivityManagerMock: LiveActivityManageable {
    func refresh() async { }
    func createActivity() { }
    func createActivity(id: String) async {}
    func stop(id: String) async {}
    func toggle(id: String) async {}
    func reset() async {}
    
    func isActivityDisabled(id: String) -> Bool { false }
    func disableActivity(id: String) {}
    func enableActivity(id: String) {}
    func toggleActivityEnabled(id: String) {}
}

struct LiveActivityManagerFactory {
    // you can also set the real user service as the default value
    #if os(iOS) && canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    static let shared: any LiveActivityManageable = LiveActivityManager()
    #else
    static let shared: any LiveActivityManageable = LiveActivityManagerMock()
    #endif
}
