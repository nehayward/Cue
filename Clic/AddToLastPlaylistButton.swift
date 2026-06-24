import SwiftUI
import SonosKit

/// One-tap shortcut to add the current item to the most recently used playlist. The icon reflects the
/// destination service (Apple Music / Spotify / Plex / Sonos). For streaming playlists it only appears
/// when the item is from the same service, since you can't add across services.
struct AddToLastPlaylistButton: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(AlertService.self) private var alertService

    var itemToAdd: PlayableContent

    /// The last-used playlist, but only when it can actually accept this item. Streaming playlists
    /// only take tracks from the same service; Sonos accepts anything.
    private var lastPlaylist: LastPlaylist? {
        guard let last = LastPlaylist.current,
              last.service == .library || last.service == itemToAdd.content.service else {
            return nil
        }
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
        case .apple, .spotify, .plex, .deezer:
            service.icon
                .frame(width: 20, height: 20)
        default:
            Image(systemName: "text.badge.plus")
        }
    }

    private func add(to playlist: LastPlaylist) {
        Task {
            alertService.showAlertContent(with: itemToAdd, subtitle: "Added to \(playlist.title)", symbolName: "plus")
            await playlist.add(itemToAdd)

            // For Sonos playlists, let tapping the toast open the playlist.
            if playlist.service == .library {
                let playlists = await sonosService.sonosPlaylists()
                if let match = playlists.first(where: { $0.id == playlist.id }) {
                    alertService.alert.handleTap = {
                        Router.main.presentedSheet = .mediaDetail(content: match, group: nil)
                    }
                }
            }
        }
    }
}
