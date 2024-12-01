import AppIntents
import CloudStorage
import SonosKit

struct SetSpeechEnhancementIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Set Speech Enhancement"
    static var description = IntentDescription(
        "When playing TV audio with a Sonos home theater speaker, you can turn on Speech Enhancement to boost the audio frequencies associated with the human voice. Turning this feature on will make dialogue easier to hear.",
        categoryName: "TV Settings"
    )
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static private var sonosService = SonosService.shared
    static private var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(title: "Speaker") var room: SonosDeviceEntity
    @Parameter(title: "Speech Enhancement") var speechEnhancement: Bool
    @Parameter(title: "Mode", default: .toggle) var mode: ToggleOption
    
    static var parameterSummary: some ParameterSummary {
        Switch(\.$mode) {
            Case(.toggle) {
                Summary("\(\.$mode) Speech Enhancement for \(\.$room)")
            }
            DefaultCase {
                Summary("\(\.$mode) Speech Enhancement for \(\.$room) \(\.$speechEnhancement) ")
            }
        }
    }
    init(room: SonosDeviceEntity, speechEnhancement: Bool) {
        self.room = room
        self.speechEnhancement = speechEnhancement
    }
    
    init() { }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in App")
        }

        do {
            if mode == .toggle {
                let current = try await Self.sonosService.getTVSettings(ip: room.ip)
                try await Self.sonosService.setDialogLevel(room.ip, enabled: !current.dialogLevel)
            } else {
                try await Self.sonosService.setDialogLevel(room.ip, enabled: speechEnhancement)
            }
        } catch {
            throw IntentError.message("Night Mode not supported")
        }
        
        try? await Task.sleep(for: .milliseconds(100))
        await Self.liveActivityManager.refresh()
        return .result(value: speechEnhancement)
    }
}
