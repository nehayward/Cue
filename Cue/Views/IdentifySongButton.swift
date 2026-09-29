import SonosKit
import SwiftUI

/// The player bar's Shazam button, shown while a station plays — on this
/// device (`group` nil) or on a speaker. ⌘⇧S from a keyboard.
///
/// Identifies in place: the logo pulses and ripples while it listens, the
/// song comes up in the banner and in Shazam History, and on this device it
/// also becomes what's on air in the player. A second tap while listening
/// stops.
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

    /// Whether the station is actually playing. The stream is sampled
    /// straight from the station, so it would match while paused too —
    /// but a paused station isn't a song anyone is asking about.
    private var isPlaying: Bool {
        group?.coordinatorRoom.isPlaying ?? playback.isPlaying
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
                .background {
                    if recognizer.isListening {
                        ListeningRipple()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: recognizer.isListening)
        }
        .accessibilityLabel(recognizer.isListening ? "Stop Identifying" : "Identify Song")
        .help(isPlaying || recognizer.isListening ? "Identify Song" : "Play the station to identify its song")
        .keyboardShortcut("s", modifiers: [.command, .shift])
        // Stays tappable while listening, so it can always be stopped.
        .disabled(!isPlaying && !recognizer.isListening)
        .onChange(of: isPlaying) { _, playing in
            if !playing, recognizer.isListening {
                recognizer.cancel()
            }
        }
    }

    private func identify() {
        if let group {
            // Listens to the station's stream from this device — the same
            // URL the speaker is playing.
            let track = group.coordinatorRoom.track
            let station = track.metadata?.stationName
            let key = "\(group.coordinatorID):\(track.metadata?.stationID ?? track.trackID)"
            recognizer.identify(stream: key) { [group] in
                await SonosService.shared.radioStreamURL(for: group)
            } onFinish: { state in
                if case .found(let song) = state {
                    RecognitionHistory.shared.record(song, station: station)
                }
                Self.announce(state)
            }
        } else {
            // Captured now, so a match that lands after the station has
            // changed isn't shown as the new one's song.
            let stationID = playback.nowPlaying?.content.id
            let station = playback.nowPlaying?.title
            recognizer.identify(stream: stationID.map { "device:\($0)" }) {
                await playback.currentStationStreamURL()
            } onFinish: { state in
                if case .found(let song) = state {
                    playback.noteRecognized(song, stationID: stationID)
                    RecognitionHistory.shared.record(song, station: station)
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

/// Rings that spread out from the Shazam logo while it listens — the
/// "hearing something" cue from Shazam's own button, so the wait for a
/// match reads as work in progress rather than a stuck tap.
private struct ListeningRipple: View {
    private static let period: Double = 1.8
    private static let rings = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .scaleEffect(1.5)
            } else {
                TimelineView(.animation) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(0..<Self.rings, id: \.self) { ring in
                            let phase = (time / Self.period + Double(ring) / Double(Self.rings))
                                .truncatingRemainder(dividingBy: 1)
                            Circle()
                                .fill(Color.accentColor.opacity(0.22 * (1 - phase)))
                                .overlay {
                                    Circle().strokeBorder(Color.accentColor.opacity(0.6 * (1 - phase)), lineWidth: 1.5)
                                }
                                .scaleEffect(0.9 + phase * 0.9)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// "Shazam History…" in a player's menu, while a station plays or once
/// there's something to look back on. Opens the list in Settings.
struct ShazamHistoryMenuButton: View {
    let router: Router
    /// The speaker group on screen, or nil for this device.
    let group: GroupRoom?

    var body: some View {
        if IdentifySongButton.isAvailable(for: group) || !RecognitionHistory.shared.entries.isEmpty {
            Button {
                router.sheet(to: .settings(destination: .recognizedSongs))
            } label: {
                Label("Shazam History…", systemImage: "shazam.logo")
            }
        }
    }
}
