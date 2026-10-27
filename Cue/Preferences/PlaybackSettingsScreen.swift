import Defaults
import SonosKit
import SwiftUI

/// Settings ▸ Playback: what Play does to the queue, what happens to it on
/// a switch between this device and a speaker, lyrics from LRCLIB, and
/// opening Cue on the player.
struct PlaybackSettingsScreen: View {
    @Environment(SonosService.self) private var sonosService

    @AppStorage(AppStorageKeys.defaultPlayAction) private var replaceQueueByDefault: Bool = false
    @AppStorage(AppStorageKeys.routeQueueTransfer) private var routeQueueTransfer: QueueTransferPreference = .ask
    @AppStorage(AppStorageKeys.lyricsOnlineLookup) private var lyricsOnlineLookup: Bool = false
    @AppStorage(AppStorageKeys.speedLaunchNowPlaying) private var speedLaunchNowPlaying: Bool = false

    var body: some View {
        Form {
            Section {
                Label {
                    Toggle(isOn: $replaceQueueByDefault) {
                        SettingsRowText(title: "Replace Queue by Default", detail: "Play Now replaces the queue instead of adding to it. Long-press for Play Next and Play Last options.")
                    }
                    .tint(.accent)
                } icon: {
                    SettingsIcon(symbol: "play.square.fill", colors: [Color(red: 0.7, green: 0.5, blue: 0.95), Color(red: 0.55, green: 0.35, blue: 0.85)])
                }

                // A switch between this device and a speaker: nothing to
                // ask about without speakers. Three choices that exclude
                // each other, so segments rather than toggles.
                if sonosService.isEnabled {
                    Label {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("When Switching Speakers")
                            Picker("When Switching Speakers", selection: $routeQueueTransfer) {
                                ForEach(QueueTransferPreference.allCases) { preference in
                                    Text(preference.title).tag(preference)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            Text(routeQueueTransfer.footnote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        SettingsIcon(symbol: "hifispeaker.arrow.forward.fill", isAsset: true, colors: [Color(red: 0.3, green: 0.8, blue: 0.55), Color(red: 0.1, green: 0.6, blue: 0.4)], padding: 7)
                    }
                }

                Label {
                    Toggle(isOn: $lyricsOnlineLookup) {
                        SettingsRowText(title: "Look Up Lyrics Online", detail: "When a song's service has no timed lyrics, Cue asks LRCLIB, sending the song's title, artist, album and length.")
                    }
                    .tint(.accent)
                } icon: {
                    SettingsIcon(symbol: "quote.bubble.fill", colors: [Color(red: 1.0, green: 0.45, blue: 0.5), Color(red: 0.9, green: 0.25, blue: 0.4)], padding: 7)
                }
            }

#if !targetEnvironment(macCatalyst) && !os(visionOS)
            // Opens the player on whatever is playing — this device or a
            // speaker — so it's here with or without Sonos.
            Section {
                Label {
                    Toggle(isOn: $speedLaunchNowPlaying) {
                        SettingsRowText(title: "Open to Now Playing", detail: "Cue opens on the player, on whatever is playing.")
                    }
                    .tint(.accent)
                } icon: {
                    SettingsIcon(symbol: "iphone", colors: [Color(red: 0.35, green: 0.6, blue: 0.95), Color(red: 0.2, green: 0.45, blue: 0.85)])
                }
            }
#endif
        }
        .navigationTitle("Playback")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
    }
}
