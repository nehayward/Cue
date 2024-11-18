import AppIntents
import UIKit
import CloudStorage
import SonosKit
#if canImport(WidgetKit)
import WidgetKit
#endif

struct LaunchAlarmsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Alarm Settings"
    static var description = IntentDescription("Open alarm settings in Clic", categoryName: "Launcher", searchKeywords: ["Launch Alarms", "Alarms"])
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in App")
        }
        
        guard
            let url = URL(string: "clic://alarms"),
            let application = UIApplication.value(forKeyPath: #keyPath(UIApplication.shared)) as? UIApplication
        else {
            return .result()
        }
        
        await application.open(url)
        return .result()
    }
}

#if !os(visionOS)
@available(iOS 18.0, *)
extension LaunchAlarmsIntent: ControlConfigurationIntent { }
#endif
