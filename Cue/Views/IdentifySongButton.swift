import SonosKit
import SwiftUI

/// The player bar's Shazam button, shown while a station plays — on this
/// device (`group` nil) or on a speaker. ⌘⇧S from a keyboard.
///
/// Identifies in place: the logo pulses while it listens, the song comes
/// up in the banner, and on this device it also becomes what's on air in
/// the player. A second tap while listening stops.
struct IdentifySongButton: View {
    /// The speaker group on screen, or nil for this device.
    let group: GroupRoom?

    private var playback: LocalPlaybackService { .shared }
    private var recognizer: SongRecognizer { .shared }

    static func isAvailable(for group: GroupRoom?) -> Bool {
        if let group {
            return !group.TVMode && group.playbackService == .radio
        }
        return LocalPlaybackService.shared.canRecognizeSong
    }

    var body: some View {
        Button {
            HapticManager.shared.fireHaptic(.buttonPress)
            if recognizer.isListening {
                recognizer.cancel()
            } else {
                identify()
            }
        } label: {
            Label(recognizer.isListening ? "Stop Identifying" : "Identify Song", systemImage: "shazam.logo.fill")
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
                .fontDesign(.rounded)
                .foregroundStyle(recognizer.isListening ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                .symbolEffect(.pulse, options: .repeating, isActive: recognizer.isListening)
        }
        .accessibilityLabel(recognizer.isListening ? "Stop Identifying" : "Identify Song")
        .help("Identify Song")
        .keyboardShortcut("s", modifiers: [.command, .shift])
    }

    private func identify() {
        if let group {
            // Listens to the station's stream from this device — the same
            // URL the speaker is playing.
            recognizer.identify { [group] in
                await SonosService.shared.radioStreamURL(for: group)
            } onFinish: { state in
                Self.announce(state)
            }
        } else {
            // Captured now, so a match that lands after the station has
            // changed isn't shown as the new one's song.
            let stationID = playback.nowPlaying?.content.id
            recognizer.identify {
                await playback.currentStationStreamURL(heard: true)
            } onFinish: { state in
                if case .found(let song) = state {
                    playback.noteRecognized(song, stationID: stationID)
                }
                Self.announce(state)
            }
        }
    }

    @MainActor
    private static func announce(_ state: SongRecognizer.State) {
        let alerts = AlertService.shared
        switch state {
        case .found(let song):
            HapticManager.shared.fireHaptic(.notification(.success))
            if let playable = song.playable {
                alerts.showAlertContent(with: playable, subtitle: "Identified by Shazam", symbolName: "shazam.logo.fill")
                if let url = song.appleMusicURL ?? song.shazamURL {
                    alerts.alert.handleTap = { UIApplication.shared.open(url) }
                }
            } else {
                let name = [song.title, song.artist].compactMap { $0 }.joined(separator: " — ")
                alerts.showAlert(with: name, imageName: "shazam.logo.fill")
            }
        case .notFound:
            HapticManager.shared.fireHaptic(.notification(.warning))
            alerts.showAlert(with: "No match — try again in a moment", imageName: "shazam.logo")
        case .failed(let message):
            HapticManager.shared.fireHaptic(.notification(.error))
            alerts.showAlert(with: message, imageName: "exclamationmark.triangle")
        case .idle, .listening:
            break
        }
    }
}
