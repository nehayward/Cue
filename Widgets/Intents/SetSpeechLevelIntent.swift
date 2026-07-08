import AppIntents
import CloudStorage
import SonosKit

struct SetSpeechLevelIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Set Speech Level"
    static var description = IntentDescription(
        "Set the speech enhancement level for an Arc Ultra soundbar. Choose Off, Low, Medium, High, or Max.",
        categoryName: "TV Settings"
    )
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static private var sonosService = SonosService.shared
    static private var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(title: "Speaker") var room: SonosDeviceEntity
    @Parameter(title: "Level", default: .low) var level: SpeechLevelOption

    static var parameterSummary: some ParameterSummary {
        Summary("Set Speech Level to \(\.$level) for \(\.$room)")
    }

    init(room: SonosDeviceEntity, level: SpeechLevelOption) {
        self.room = room
        self.level = level
    }

    init() { }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in App")
        }

        do {
            try await Self.sonosService.setArcUltraSpeechLevel(room.ip, level: level.rawValue)
        } catch {
            throw IntentError.message("Speech Level not supported")
        }

        try? await Task.sleep(for: .milliseconds(100))
        await Self.liveActivityManager.refresh()
        return .result(value: level.rawValue)
    }
}
