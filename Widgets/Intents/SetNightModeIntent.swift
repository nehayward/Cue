import AppIntents
import CloudStorage
import SonosKit

struct SetNightModeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Set Night Mode"
    static var description = IntentDescription("Set Night Mode for Soundbars", categoryName: "TV Settings")
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    static private var sonosService = SonosService.shared
    static private var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(title: "Speaker") var room: SonosDeviceEntity
    @Parameter(title: "Night Mode") var nightMode: Bool
    @Parameter(title: "Mode", default: .toggle) var mode: ToggleOption
    
    static var parameterSummary: some ParameterSummary {
        Switch(\.$mode) {
            Case(.toggle) {
                Summary("\(\.$mode) Night Mode for \(\.$room)")
            }
            DefaultCase {
                Summary("\(\.$mode) Night Mode for \(\.$room) \(\.$nightMode) ")
            }
        }
    }

    init(room: SonosDeviceEntity, nightMode: Bool) {
        self.room = room
        self.nightMode = nightMode
    }

    init() { }

    func perform() async throws -> some IntentResult {
        guard CloudStorageSync.shared.bool(for: "com.cue.subscriptions") ?? false else {
            throw IntentError.message("Subscribe to Super in App")
        }

        do {
            if mode == .toggle {
                let current = try await Self.sonosService.getTVSettings(ip: room.ip)
                try await Self.sonosService.setNightMode(room.ip, enabled: !current.nightMode)
            } else {
                try await Self.sonosService.setNightMode(room.ip, enabled: nightMode)
            }
        } catch {
            throw IntentError.message("Night Mode not supported")
        }

        try? await Task.sleep(for: .milliseconds(100))
        await Self.liveActivityManager.refresh()
        return .result()
    }
}
