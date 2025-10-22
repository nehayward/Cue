import AppIntents
import CloudStorage
import SonosKit

struct GroupIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Group Speakers"
    
    static var description = IntentDescription(
        "Group selected Sonos speakers so they play the same audio together.",
        categoryName: "Playback",
        searchKeywords: ["Sonos", "Speakers", "Group", "Link", "Playback"]
    )
    
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    
    @Parameter(
        title: "Speakers to Group",
        description: "Choose one or more Sonos speakers to group for synchronized playback."
    )
    var rooms: [SonosDeviceEntity]
    
    static var parameterSummary: some ParameterSummary {
        Summary("Group \(\.$rooms)")
    }
    
    init(rooms: [SonosDeviceEntity]) {
        self.rooms = rooms
    }

    init() { }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in Clic to use this action.")
        }
        
        let rooms = rooms.map(\.toRoom)
        _ = await SonosService.shared.speedGroup(rooms: rooms)
        return .result()
    }
}
