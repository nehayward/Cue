import AppIntents
import UIKit
import CloudStorage
import SonosKit
#if canImport(WidgetKit)
import WidgetKit
#endif

struct LaunchSpeakerIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open Sonos Speaker"
    static var description: IntentDescription = "Open a specific Sonos speaker."

    @Parameter(title: "Sonos Speaker", description: "Select the Sonos speaker you want to control")
    var target: SonosDeviceEntity

    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard
            let url = URL(string: "clic://device?id=\(target.id)"),
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
extension LaunchSpeakerIntent: ControlConfigurationIntent { }
#endif
