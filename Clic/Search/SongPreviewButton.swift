import SwiftUI
import Defaults

/// Context menu peek preview for a track. Mirrors the PlayableContentView cell
/// layout (artwork + title + subtitle) and adds a 2px accent-color progress bar
/// that fills as the preview clip plays. onDisappear stops the preview when the
/// menu is dismissed — reliable here because the preview view is rendered by
/// UIKit as a proper view controller, unlike menu item views which are snapshotted.
struct SongPreviewCard: View {
    @Environment(AudioPlaybackService.self) private var audioService
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
            audioService.stopPreview()
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
///
/// Stop-on-dismiss is handled at two points:
/// • contextMenu: SongPreviewCard.onDisappear (reliable UIKit view lifecycle)
/// • ellipsis Menu: PlayableMenuView.onDisappear on OpenInServiceView
struct SongPreviewButton: View {
    @Environment(AudioPlaybackService.self) private var audioService
    @AppStorage(Defaults.AppStorageKeys.autoPreviewSongs) private var autoPreviewEnabled = false

    let previewURL: URL

    var body: some View {
        Button {
            Task { await audioService.preview(url: previewURL) }
        } label: {
            Label("Preview Song", systemImage: "play.circle")
        }
        .menuActionDismissBehavior(.disabled)
        .task {
            guard autoPreviewEnabled else { return }
            await audioService.preview(url: previewURL)
        }

        Button {
            autoPreviewEnabled.toggle()
        } label: {
            Label("Auto-Preview", systemImage: autoPreviewEnabled ? "checkmark.circle.fill" : "circle")
        }
    }
}
