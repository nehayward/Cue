import WidgetKit
import SwiftUI

/// Cue's widgets on the iPhone and iPad: the book shelf, Albums and
/// Discography.
///
/// The Sonos remote, scene, Now Playing and control widgets and the Live
/// Activity in this folder aren't built into the extension (see the target's
/// membership exceptions): they only work with a speaker, and Cue offers
/// nothing that needs one. Their intents are still built into the app for
/// Shortcuts.
@main
struct CueWidgetBundle: WidgetBundle {
    var body: some Widget {
        BookShelfWidget()
        AlbumShelfWidget()
        DiscographyWidget()
    }
}
