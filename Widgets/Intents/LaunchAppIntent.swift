import AppIntents
import UIKit
import CloudStorage
import SonosKit
#if canImport(WidgetKit)
import WidgetKit
#endif

struct LaunchSpeakerIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Sonos Speaker"
    static var description = IntentDescription("Open a specific Sonos speaker.", categoryName: "Launcher", searchKeywords: ["Launch Speaker"])

    @Parameter(title: "Sonos Speaker", description: "Select the Sonos speaker you want to control")
    var room: SonosDeviceEntity?

    static let openAppWhenRun: Bool = true
    
    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$room)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in App")
        }
        
        guard let room = room else {
            let rooms = SonosService.shared.rooms
            let selectedRoom = try await $room.requestDisambiguation(among: rooms.map {
                SonosDeviceEntity(id: $0.id, ip: $0.ip, name: $0.name)
            })
            
            return await openRoom(selectedRoom.id)
        }
        
        return await openRoom(room.id)
    }
    
    @MainActor
    private func openRoom(_ id: String) async -> some IntentResult {
        guard
            let url = URL(string: "clic://device?id=\(id)"),
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
