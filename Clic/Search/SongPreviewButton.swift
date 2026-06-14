import SwiftUI

/// Context-menu option for auditioning a track's short preview clip.
///
/// Tapping toggles the preview without dismissing the menu, and the preview
/// stops automatically when the menu is dismissed. Preview audio plays in a
/// mixed, ambient session so it layers over anything already playing.
struct SongPreviewButton: View {
    @Environment(AudioPlaybackService.self) private var audioService

    let previewURL: URL

    private var isPreviewing: Bool {
        audioService.isPreviewing(previewURL)
    }

    var body: some View {
        Button {
            if isPreviewing {
                audioService.stop()
            } else {
                Task { await audioService.preview(url: previewURL) }
            }
        } label: {
            Label(
                isPreviewing ? "Stop Preview" : "Preview Song",
                systemImage: isPreviewing ? "stop.circle.fill" : "play.circle"
            )
        }
        .menuActionDismissBehavior(.disabled)
        .onDisappear {
            if isPreviewing {
                audioService.stop()
            }
        }
    }
}
