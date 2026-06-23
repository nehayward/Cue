import SwiftUI
import Defaults

/// Context menu peek preview for a track. Mirrors the PlayableContentView cell
/// layout (artwork + title + subtitle) and adds a 2px accent-color progress bar
/// that fills as the preview clip plays.
///
/// Uses AudioPlaybackService.shared directly rather than environment so it is
/// safe inside context menu preview views, which may not inherit all environment
/// values from their parent.
struct SongPreviewCard: View {
    // @State on an @Observable reference type ensures SwiftUI tracks property
    // accesses and re-renders when playbackProgress / duration change.
    @State private var audioService = AudioPlaybackService.shared
    let item: PlayableContent

    private var progressFraction: Double {
        guard audioService.isPreviewMode, audioService.duration > 0 else { return 0 }
        return min(1, audioService.playbackProgress / audioService.duration)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Color.accentColor)
                .scaleEffect(x: progressFraction, anchor: .leading)
                .frame(maxWidth: .infinity, minHeight: 2, maxHeight: 2)
                .animation(.linear(duration: 0.3), value: progressFraction)
        }
        .onDisappear {
            AudioPlaybackService.shared.stopPreview()
        }
    }
}

/// Context-menu and ellipsis-menu option for auditioning a track's preview clip.
///
/// - "Preview Song" plays the clip; the menu stays open.
/// - "Auto-Preview" (off by default) starts clips automatically on menu open.
///   It is a dismiss-on-tap button (matching FavoriteMenuButton) because
///   SwiftUI context menus snapshot their content — a Toggle with dismiss
///   disabled never updates its checkmark while open.
struct SongPreviewButton: View {
    @AppStorage(Defaults.AppStorageKeys.autoPreviewSongs) private var autoPreviewEnabled = false

    let previewURL: URL

    var body: some View {
        Button {
            Task { await AudioPlaybackService.shared.preview(url: previewURL) }
        } label: {
            Label("Preview Song", systemImage: "play.circle")
        }
        .menuActionDismissBehavior(.disabled)
        .task {
            guard autoPreviewEnabled else { return }
            await AudioPlaybackService.shared.preview(url: previewURL)
        }

        Button {
            autoPreviewEnabled.toggle()
        } label: {
            Label("Auto-Preview", systemImage: autoPreviewEnabled ? "checkmark.circle.fill" : "circle")
        }
    }
}
