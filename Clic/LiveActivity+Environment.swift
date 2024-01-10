import SwiftUI

protocol LiveActivityManageable {
    func refresh(type: UpdateType) async
    func createActivity()
    func createActivity(id: String) async
}

struct LiveActivityManagerKey: EnvironmentKey {
    // you can also set the real user service as the default value
    #if os(iOS) && canImport(ActivityKit)
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
    func refresh(type: UpdateType) async { }
    func createActivity() { }
    func createActivity(id: String) async {}
}

struct LiveActivityManagerFactory {
    // you can also set the real user service as the default value
    #if os(iOS) && canImport(ActivityKit)
    static let shared: any LiveActivityManageable = LiveActivityManager()
    #else
    static let shared: any LiveActivityManageable = LiveActivityManagerMock()
    #endif
}
