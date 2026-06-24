import SwiftUI
import SonosKit
import Defaults

/// Context menu peek preview for a track. Mirrors the PlayableContentView cell
/// layout (artwork + title + subtitle) and uses the same left-anchored accent
/// background fill that grows as the preview clip plays.
///
/// The progress fill and text styling intentionally read their layout/styling
/// values from their parent.
struct SongPreviewCard: View {
    // @State on an @Observable reference type ensures SwiftUI tracks property
    // accesses and re-renders when playbackProgress / duration change.
    @State private var audioService = AudioPlaybackService.shared
    let item: PlayableContent

    private var progressFraction: Double {
        guard let url = item.previewURL,
              audioService.isPreviewing(url),
              audioService.duration > 0 else { return 0 }
        return min(1, audioService.playbackProgress / audioService.duration)
    }

    var body: some View {
        HStack(spacing: 8) {
            ContentArtworkView(content: item, showMusicSource: false)
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(1)
                    .fontDesign(.rounded)

                Text(item.subtitle.isEmpty ? item.content.type.title : item.subtitle)
                    .lineLimit(1)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fontDesign(.rounded)
            }

            Spacer(minLength: 0)
        }
        .background(alignment: .leading) {
            Color.accentColor.opacity(0.12)
                .scaleEffect(x: progressFraction, anchor: .leading)
                .animation(.linear(duration: 0.3), value: progressFraction)
        }
    }
}

/// Context-menu and ellipsis-menu option for auditioning a track's preview clip.
///
/// "Preview Song" plays the clip and keeps the menu open. When the
/// `autoPreviewSongs` setting (toggled in Preferences → Playback) is on, the
/// clip starts automatically as soon as the menu opens.
struct SongPreviewButton: View {
    @AppStorage(Defaults.AppStorageKeys.autoPreviewSongs) private var autoPreviewEnabled = false

    let previewURL: URL

    var body: some View {
        Button {
            AudioPlaybackService.shared.preview(url: previewURL)
        } label: {
            Label("Preview Song", systemImage: "music.note")
        }
        .menuActionDismissBehavior(.disabled)
        .onAppear {
            guard autoPreviewEnabled else { return }
            AudioPlaybackService.shared.preview(url: previewURL)
        }
    }
}
