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
            // Try Arc Ultra path first; getTVSettings(isArcUltra:true) throws on
            // non-Arc-Ultra devices (unsupported EQ type returns SOAP 500).
            if let arcSettings = try? await Self.sonosService.getTVSettings(ip: room.ip, isArcUltra: true) {
                let enable = mode == .toggle ? !arcSettings.speechLevel.isActive : speechEnhancement
                let level = enable ? max(1, arcSettings.dialogLevelValue) : 0
                try await Self.sonosService.setArcUltraSpeechLevel(room.ip, level: level)
            } else {
                let current = try await Self.sonosService.getTVSettings(ip: room.ip)
                let enable = mode == .toggle ? !current.dialogLevel : speechEnhancement
                try await Self.sonosService.setDialogLevel(room.ip, enabled: enable)
            }
        } catch {
            throw IntentError.message("Speech Enhancement not supported")
        }

        try? await Task.sleep(for: .milliseconds(100))
        await Self.liveActivityManager.refresh()
        return .result(value: speechEnhancement)
    }
}
