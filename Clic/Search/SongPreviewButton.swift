import SwiftUI
import Defaults

/// Context-menu controls for auditioning a track's short preview clip.
///
/// - "Preview Song" plays the clip; the menu stays open. The preview stops
///   when the menu is dismissed.
/// - "Auto-Preview" (off by default) starts clips automatically when a track's
///   menu opens. It is a dismiss-on-tap button so its checkmark state renders
///   correctly on reopen (SwiftUI context menus snapshot their content and
///   don't re-render in place).
///
/// Two mechanisms handle stop-on-dismiss reliably:
/// 1. `.task` for auto-preview — it is automatically cancelled by SwiftUI when
///    the view disappears, aborting the in-flight URLSession request before
///    audio can start.
/// 2. `onDisappear` calling `stopPreview()` for audio that is already playing.
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
        .onDisappear {
            audioService.stopPreview()
        }

        Button {
            autoPreviewEnabled.toggle()
        } label: {
            Label("Auto-Preview", systemImage: autoPreviewEnabled ? "checkmark.circle.fill" : "circle")
        }
    }
}
