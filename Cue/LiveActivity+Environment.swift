import SwiftUI

protocol LiveActivityManageable {
    func refresh() async
    func createActivity(shouldLoad: Bool)
    func createActivity(id: String) async
    func stop(id: String) async
    func endAll() async 
    func toggle(id: String) async
    func reset() async
    
    func isActivityDisabled(id: String) -> Bool
    func disableActivity(id: String)
    func enableActivity(id: String)
    func toggleActivityEnabled(id: String)
}

struct LiveActivityManagerKey: EnvironmentKey {
    // Live Activities are off for now: the Lock Screen relies on the system
    // Now Playing card instead, and the Widgets extension that draws them isn't
    // embedded. Swap `LiveActivityManager()` back in here and in
    // `LiveActivityManagerFactory` to bring them back.
    static let defaultValue: any LiveActivityManageable = LiveActivityManagerMock()
}

extension EnvironmentValues {
    var liveActivityManager: any LiveActivityManageable {
        get { self[LiveActivityManagerKey.self] }
        set { self[LiveActivityManagerKey.self] = newValue }
    }
}

final class LiveActivityManagerMock: LiveActivityManageable {
    func refresh() async { }
    func createActivity(shouldLoad: Bool) { }
    func createActivity(id: String) async {}
    func stop(id: String) async {}
    func endAll() async {}
    func toggle(id: String) async {}
    func reset() async {}
    
    func isActivityDisabled(id: String) -> Bool { false }
    func disableActivity(id: String) {}
    func enableActivity(id: String) {}
    func toggleActivityEnabled(id: String) {}
}

struct LiveActivityManagerFactory {
    // Off for now — see `LiveActivityManagerKey`.
    static let shared: any LiveActivityManageable = LiveActivityManagerMock()
}
