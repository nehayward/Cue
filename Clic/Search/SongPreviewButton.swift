import SwiftUI

/// Context-menu option for auditioning a track's short preview clip.
///
/// The preview starts automatically when the menu appears and keeps playing —
/// even after the menu is dismissed — until the user taps the option again to
/// stop it, so they can quickly audition one song after another. Tapping never
/// dismisses the menu. Preview audio plays in a mixed, ambient session so it
/// layers over anything already playing.
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
        .onAppear {
            Task { await audioService.preview(url: previewURL) }
        }
    }
}
