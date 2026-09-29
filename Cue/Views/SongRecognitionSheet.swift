import NukeUI
import SonosKit
import SwiftUI

/// Names the song on a radio station: listens as soon as it opens, then
/// shows what Shazam found — the catalog row to play, queue or add to a
/// playlist, and links out to Apple Music and Shazam.
struct SongRecognitionSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// The station's name, for "Listening to …".
    var stationName: String?
    let resolveStream: @MainActor () async -> URL?
    var onFound: @MainActor (RecognizedSong) -> Void = { _ in }

    private var recognizer: SongRecognizer { .shared }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Identify Song")
#if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { identify() }
        .onDisappear { recognizer.cancel() }
    }

    private func identify() {
        recognizer.identify(stream: resolveStream, onFound: onFound)
    }

    @ViewBuilder
    private var content: some View {
        switch recognizer.state {
        case .idle, .listening:
            VStack(spacing: 16) {
                Image(systemName: "shazam.logo.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, options: .repeating)
                Text(stationName.map { "Listening to \($0)…" } ?? "Listening…")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .padding()
        case .found(let song):
            found(song)
        case .notFound:
            ContentUnavailableView {
                Label("No Match", systemImage: "shazam.logo")
            } description: {
                Text("Shazam couldn't name what's on air. It may be talk, an ad, or a song it doesn't know.")
            } actions: {
                Button("Try Again", action: identify)
                    .buttonStyle(.bordered)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Can't Identify", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", action: identify)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func found(_ song: RecognizedSong) -> some View {
        List {
            Section {
                VStack(spacing: 8) {
                    LazyImage(url: song.artworkURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 2)

                    Text(song.title)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    if let artist = song.artist {
                        Text(artist)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            // The catalog row carries play, queue and playlist actions, the
            // same as any search result.
            if let playable = song.playable {
                Section {
                    PlayableContentView(item: playable)
                }
            }

            Section {
                if let url = song.appleMusicURL {
                    Link(destination: url) {
                        Label("Open in Apple Music", systemImage: "arrow.up.forward.app")
                    }
                }
                if let url = song.shazamURL {
                    Link(destination: url) {
                        Label("Open in Shazam", systemImage: "shazam.logo")
                    }
                }
                Button("Identify Again", systemImage: "arrow.clockwise", action: identify)
            }
        }
    }
}

/// The player bar's Shazam button, shown while a station plays — on this
/// device (`group` nil) or on a speaker. ⌘⇧S from a keyboard.
struct IdentifySongButton: View {
    /// The speaker group on screen, or nil for this device.
    let group: GroupRoom?

    @State private var isPresented = false

    private var playback: LocalPlaybackService { .shared }

    static func isAvailable(for group: GroupRoom?) -> Bool {
        if let group {
            return !group.TVMode && group.playbackService == .radio
        }
        return LocalPlaybackService.shared.canRecognizeSong
    }

    var body: some View {
        Button {
            HapticManager.shared.fireHaptic(.buttonPress)
            isPresented = true
        } label: {
            Label("Identify Song", systemImage: "shazam.logo.fill")
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
                .fontDesign(.rounded)
        }
        .accessibilityLabel("Identify Song")
        .help("Identify Song")
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .sheet(isPresented: $isPresented) {
            sheet
        }
    }

    @ViewBuilder
    private var sheet: some View {
        if let group {
            // Listens to the station's stream from this device — the same
            // URL the speaker is playing.
            SongRecognitionSheet(stationName: group.coordinatorRoom.radioStation) { [group] in
                await SonosService.shared.radioStreamURL(for: group)
            }
        } else {
            // Captured now, so a match that lands after the station has
            // changed isn't shown as the new one's song.
            let stationID = playback.nowPlaying?.content.id
            SongRecognitionSheet(stationName: playback.nowPlaying?.title) {
                await playback.currentStationStreamURL()
            } onFound: { song in
                playback.noteRecognized(song, stationID: stationID)
            }
        }
    }
}
