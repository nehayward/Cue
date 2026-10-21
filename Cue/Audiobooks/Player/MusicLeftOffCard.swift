import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// In each music library while a book plays on this device: the music it
/// was started over, Where You Left Off, one tap from playing again at the
/// song and spot it was left on. Nothing otherwise.
struct MusicLeftOffCard: View {
    @State private var player = AudiobookPlayer.shared

    var body: some View {
        if let aside = player.musicSetAside {
            VStack(alignment: .leading, spacing: 10) {
                Text("Where You Left Off")
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    Task { try? await player.returnToMusic() }
                } label: {
                    HStack(spacing: 12) {
                        if let song = aside.nowPlaying {
                            ContentArtworkView(content: song, showMusicSource: false, preferredSize: 160, cornerRadius: 8)
                                .frame(width: 56, height: 56)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(aside.title)
                                .font(.headline)
                                .lineLimit(1)
                            if let line = aside.songLine {
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.tint)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(aside.title) from where you left it")
            }
            .padding(16)
            .background(.fill.quaternary, in: .rect(cornerRadius: 20))
            // A section of its own, as wide as the library's group under it:
            // the list's spacing between sections is the room around it.
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }
}
