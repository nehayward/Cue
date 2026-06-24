import SwiftUI

/// Ellipsis-menu / context-menu option for auditioning a track's preview clip.
/// An explicit tap plays the clip and keeps the menu open; the leading-swipe
/// "Preview" action on the row is the other way in. Both are deliberate user
/// actions — there's no auto-on-open behaviour, which SwiftUI can't trigger
/// reliably without fighting the menu's view lifecycle.
struct SongPreviewButton: View {
    let previewURL: URL

    var body: some View {
        Button {
            AudioPlaybackService.shared.preview(url: previewURL)
        } label: {
            Label("Preview Song", systemImage: "music.note")
        }
        .menuActionDismissBehavior(.disabled)
    }
}
