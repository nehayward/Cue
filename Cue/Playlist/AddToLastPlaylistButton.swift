import SwiftUI
import SonosKit

/// One-tap shortcut to add the current item to the most recently used playlist. The icon reflects the
/// destination service (Apple Music / Spotify / Plex / Sonos). For streaming playlists it only appears
/// when the item is from the same service, since you can't add across services.
struct AddToLastPlaylistButton: View {
    var itemToAdd: PlayableContent

    /// The last-used playlist, but only when it can actually accept this item
    /// (`LastPlaylist.accepts`).
    private var lastPlaylist: LastPlaylist? {
        guard let last = LastPlaylist.current, last.accepts(itemToAdd) else { return nil }
        return last
    }

    var body: some View {
        if let lastPlaylist {
            Button {
                add(to: lastPlaylist)
            } label: {
                Label {
                    Text("Add to \(lastPlaylist.title)")
                } icon: {
                    icon(for: lastPlaylist.service)
                }
            }
        }
    }

    @ViewBuilder
    private func icon(for service: MusicService) -> some View {
        switch service {
        case .apple, .spotify, .plex, .deezer, .subsonic, .files:
            // Use `image` (not `icon`): its macCatalyst branch pre-resizes the UIImage so it
            // doesn't render oversized in menus, matching OpenInServiceView.
            service.image
                .frame(width: 20, height: 20)
        default:
            Image(systemName: "text.badge.plus")
        }
    }

    private func add(to playlist: LastPlaylist) {
        Task {
            await playlist.addAndAnnounce(itemToAdd)
        }
    }
}
