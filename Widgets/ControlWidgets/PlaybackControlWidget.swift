import AppIntents
import SonosKit
import SwiftUI
import WidgetKit

// MARK: - Configuration intent

/// What the user configures when adding the control: which speaker it targets.
@available(iOS 18.0, *)
struct PlaybackControlConfiguration: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Playback Control"
    static var description = IntentDescription("Choose the Sonos speaker this control plays and pauses.")

    @Parameter(
        title: "Speaker",
        requestDisambiguationDialog: IntentDialog("Which speaker would you like to control?")
    )
    var room: SonosDeviceEntity?

    init() { }
}

// MARK: - Toggle action

/// Plays or pauses the configured speaker. The control's toggle sets `value`
/// to the desired state before running this.
@available(iOS 18.0, *)
struct SetPlaybackIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Set Sonos Playback"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Speaker") var room: SonosDeviceEntity?
    @Parameter(title: "Playing") var value: Bool

    init() { }

    init(room: SonosDeviceEntity?) {
        self.room = room
    }

    func perform() async throws -> some IntentResult {
        guard let room,
              let group = await SonosService.shared.getGroupCoordinatorWithRoom(roomID: room.id) else {
            return .result()
        }
        if value {
            await SonosService.shared.play(ip: group.ip)
        } else {
            await SonosService.shared.pause(ip: group.ip)
        }
        return .result()
    }
}

// MARK: - Live value

/// Snapshot the control renders: the speaker and whether it's currently playing.
@available(iOS 18.0, *)
struct PlaybackControlValue {
    var isPlaying: Bool
    var room: SonosDeviceEntity?
}

/// Supplies the control's live playing state for its configured speaker.
@available(iOS 18.0, *)
struct PlaybackControlValueProvider: AppIntentControlValueProvider {
    func previewValue(configuration: PlaybackControlConfiguration) -> PlaybackControlValue {
        PlaybackControlValue(isPlaying: false, room: configuration.room)
    }

    func currentValue(configuration: PlaybackControlConfiguration) async throws -> PlaybackControlValue {
        guard let room = configuration.room else {
            return PlaybackControlValue(isPlaying: false, room: nil)
        }
        // `GroupRoom.coordinatorRoom.isPlaying` is cached and goes stale —
        // query the live transport state of the group's coordinator instead.
        let group = await SonosService.shared.getGroupCoordinatorWithRoom(roomID: room.id)
        let ip = group?.ip ?? room.ip

        // GetTransportInfo briefly reports `.transitioning` right after a
        // play/pause or a track change. Re-poll so the control settles on the
        // real state instead of flashing the wrong one.
        var status = await SonosService.shared.getPlaybackInfo(ip: ip)
        var attempts = 0
        while status == .transitioning, attempts < 3 {
            try? await Task.sleep(for: .milliseconds(100))
            status = await SonosService.shared.getPlaybackInfo(ip: ip)
            attempts += 1
        }
        return PlaybackControlValue(isPlaying: status == .playing, room: room)
    }
}

// MARK: - Control widget

@available(iOS 18.0, *)
struct PlaybackControlWidget: ControlWidget {
    static let kind: String = "com.clic.PlaybackControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: PlaybackControlValueProvider()
        ) { value in
            ControlWidgetToggle(
                isOn: value.isPlaying,
                action: SetPlaybackIntent(room: value.room)
            ) {
                Label {
                    // Speaker names are shown verbatim; the fallback is a
                    // string literal so it localises via the String Catalog.
                    if let name = value.room?.name {
                        Text(name)
                    } else {
                        Text("Choose Speaker")
                    }
                } icon: {
                    Image(systemName: value.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                }
                .controlWidgetActionHint(Text(value.isPlaying ? "Pause" : "Play"))
            } valueLabel: { isPlaying in
                // Replaces the toggle's default "On"/"Off" state text.
                Text(isPlaying ? "Playing" : "Paused")
            }
            .tint(.teal)
        }
        .displayName("Playback")
        .description("Play or pause a Sonos speaker. Must be on Wi-Fi with your Sonos system.")
        .promptsForUserConfiguration()
    }
}
