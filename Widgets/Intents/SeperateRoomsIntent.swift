import AppIntents
import CloudStorage
import SonosKit
#if canImport(WidgetKit)
import WidgetKit
#endif

struct SeparateRoomsIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Separate Speakers"
    
    static var description = IntentDescription(
        "Ungroup selected Sonos speakers so they play independently.",
        categoryName: "Playback",
        searchKeywords: ["Sonos", "Speakers", "Ungroup", "Separate", "Playback"]
    )
    
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    private static var liveActivityManager = LiveActivityManagerFactory.shared
    
    @Parameter(
        title: "Speakers to Separate",
        description: "Choose one or more Sonos speakers to remove from their current group."
    )
    var rooms: [SonosDeviceEntity]
    
    static var parameterSummary: some ParameterSummary {
        Summary("Separate \(\.$rooms)")
    }
    
    init(rooms: [SonosDeviceEntity]) {
        self.rooms = rooms
    }

    init() { }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Clic to use this action.")
        }
        
        var rooms = rooms.map(\.toRoom)
        for group in rooms.map(\.toGroup) {
            await SonosService.shared.ungroup(group: group)
        }
        return .result()
    }
}
