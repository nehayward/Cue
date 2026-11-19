import AppIntents
import Defaults
import SonosKit
#if canImport(WidgetKit)
import WidgetKit
#endif

struct PlayIntent: LiveActivityIntent {
    static var isDiscoverable: Bool = false
    static var title: LocalizedStringResource = "Play Item"
    static var description: IntentDescription = "Play an item from your history on a speaker."
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(title: "Sonos Speaker") var room: SonosDeviceEntity
    
    @Parameter(title: "ID")
    private var id: String
    
    @Parameter(title: "Title")
    private var title: String
    
    @Parameter(title: "Service")
    private var service: String
    
    @Parameter(title: "Type")
    private var type: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Play item on \(\.$room)")
    }
    
    init(room: SonosDeviceEntity, title: String, id: String, service: String, type: String) {
        self.room = room
        self.title = title
        self.id = id
        self.service = service
        self.type = type
    }

    init() { }

    func perform() async throws -> some IntentResult {
        guard GroupStorageKeys.defaults.hasSuper else {
            throw IntentError.superRequired
        }
        
        guard let group = await SonosService.shared.getGroupCoordinatorWithRoom(roomID: room.id) else {
            throw IntentError.message("Failed to lookup Room")
        }
        
        let item = PlayableContent(title: "", subtitle: "", thumbnail: nil, artwork: nil, content: MediaContent(service: MusicService(service: service)!, id: id, type: ContentType(type)!, location: nil))
        // As a tap on it in Cue: Play Now, or Replace Queue when that's the
        // choice in Settings (a playlist always replaces). It was Play Next,
        // so over a song already playing the widget's Play only lined it
        // up, and it played once Next was pressed.
        let position = QueuePosition.defaultPosition(
            for: item.content.type,
            replaceQueueByDefault: UserDefaults.standard.bool(forKey: AppStorageKeys.defaultPlayAction)
        )
        try await SonosService.shared.queue(playable: item, group: group, position: position)
        await SonosService.shared.play(ip: group.coordinatorRoom.ip)
        
        #if canImport(WidgetKit)

        if #available(visionOS 26.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
        return .result()
    }
}
