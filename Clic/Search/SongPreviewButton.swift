import SwiftUI
import Defaults

/// Context-menu controls for auditioning a track's short preview clip.
///
/// - "Preview Song" plays the clip while the menu stays open (it doesn't
///   dismiss the menu); the preview stops automatically when the menu is
///   dismissed.
/// - "Auto-Preview" is a persisted checkmark setting (off by default). When on,
///   opening a track's menu starts the clip automatically.
///
/// SwiftUI context menus render their content as a static snapshot, so the
/// Auto-Preview control is a dismiss-on-tap button (matching `FavoriteMenuButton`)
/// rather than an in-place `Toggle`, which would never visually update while the
/// menu is open. Preview audio plays in a mixed, ambient session so it layers
/// over anything already playing.
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
        .onAppear {
            guard autoPreviewEnabled else { return }
            Task { await audioService.preview(url: previewURL) }
        }
        .onDisappear {
            if audioService.isPreviewing(previewURL) {
                audioService.stop()
            }
        }

        Button {
            autoPreviewEnabled.toggle()
        } label: {
            Label("Auto-Preview", systemImage: autoPreviewEnabled ? "checkmark.circle.fill" : "circle")
        }
    }
}
