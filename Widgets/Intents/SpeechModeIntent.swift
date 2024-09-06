import AppIntents
import CloudStorage
import SonosKit

struct SpeechEnhancementIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Speech Enhancement"
    static var description: IntentDescription = "When playing TV audio with a Sonos home theater speaker, you can turn on Speech Enhancement to boost the audio frequencies associated with the human voice. Turning this feature on will make dialogue easier to hear."
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static var sonosService = SonosService()
    static var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(title: "Sonos Speaker") var room: SonosDeviceEntity
    @Parameter(title: "Speech Enhancement") var speechEnhancement: Bool

    init(room: SonosDeviceEntity, speechEnhancement: Bool) {
        self.room = room
        self.speechEnhancement = speechEnhancement
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Toggle night mode for \(\.$room)")
    }

    init() { }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in App")
        }

        guard let coordinatorRoom = await Self.sonosService.getGroupCoordinatorWithRoom(roomID: room.id) else {
            throw IntentError.message("Failed to lookup Room")
        }

        do {
            try await Self.sonosService.setDialogLevel(coordinatorRoom.ip, enabled: speechEnhancement)
        } catch {
            throw IntentError.message("Night Mode not supported")
        }

        try? await Task.sleep(for: .milliseconds(250))
        await Self.liveActivityManager.refresh(type: .refresh)
        return .result(value: speechEnhancement)
    }
}
