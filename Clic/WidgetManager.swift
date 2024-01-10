import SwiftUI

protocol WidgetManageable {
    func refresh(type: UpdateType) async
//    func reloadTimelines(
}

//enum WidgetFactory {
//    // you can also set the real user service as the default value
//    #if os(iOS) && canImport(ActivityKit)
//    static let shared: any WidgetManageable = WidgetManageable()
//    #else
//    static let shared: any WidgetManageable = LiveActivityManagerMock()
//    #endif
//}

//
//struct LiveActivityManagerKey: EnvironmentKey {
//    // you can also set the real user service as the default value
//    #if os(iOS) && canImport(ActivityKit)
//    static let defaultValue: any LiveActivityManageable = LiveActivityManager()
//    #else
//    static let defaultValue: any LiveActivityManageable = LiveActivityManagerMock()
//    #endif
//}
//
//extension EnvironmentValues {
//    var liveActivityManager: any LiveActivityManageable {
//        get { self[LiveActivityManagerKey.self] }
//        set { self[LiveActivityManagerKey.self] = newValue }
//    }
//}
//
//final class LiveActivityManagerMock: LiveActivityManageable {
//    func refresh(type: UpdateType) async { }
//    func createActivity() { }
//    func createActivity(id: String) async {}
//}
//
