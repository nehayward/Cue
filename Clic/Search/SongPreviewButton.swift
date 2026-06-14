import SwiftUI
import Defaults

/// Context-menu controls for auditioning a track's short preview clip.
///
/// The "Auto-Preview" toggle (a checkmark option, off by default) controls
/// whether the preview starts automatically when a track's menu appears. When
/// enabled, opening a menu plays the clip right away and toggling another track
/// swaps to it, so users can quickly audition one song after another. Previews
/// keep playing after the menu is dismissed and stop only when the user taps
/// the option again. Tapping never dismisses the menu. Preview audio plays in a
/// mixed, ambient session so it layers over anything already playing.
struct SongPreviewButton: View {
    @Environment(AudioPlaybackService.self) private var audioService
    @AppStorage(Defaults.AppStorageKeys.autoPreviewSongs) private var autoPreviewEnabled = false

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
            guard autoPreviewEnabled else { return }
            Task { await audioService.preview(url: previewURL) }
        }

        Toggle(isOn: $autoPreviewEnabled) {
            Label("Auto-Preview", systemImage: "wand.and.stars")
        }
        .menuActionDismissBehavior(.disabled)
        .onChange(of: autoPreviewEnabled) { _, enabled in
            if enabled {
                Task { await audioService.preview(url: previewURL) }
            } else if isPreviewing {
                audioService.stop()
            }
        }
    }
}
