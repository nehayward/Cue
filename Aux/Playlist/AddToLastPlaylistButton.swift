import SwiftUI
import SonosKit

/// One-tap shortcut to add the current item to the most recently used playlist. The icon reflects the
/// destination service (Apple Music / Spotify / Plex / Sonos). For streaming playlists it only appears
/// when the item is from the same service, since you can't add across services.
struct AddToLastPlaylistButton: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(AlertService.self) private var alertService

    var itemToAdd: PlayableContent

    /// The last-used playlist, but only when it can actually accept this item. Sonos accepts
    /// anything; streaming playlists only take tracks from the same service (never albums, which
    /// the song-add endpoints can't handle).
    private var lastPlaylist: LastPlaylist? {
        guard let last = LastPlaylist.current else { return nil }
        if last.service == .library { return last }
        guard last.service == itemToAdd.content.service,
              [.track, .libraryTrack].contains(itemToAdd.content.type) else { return nil }
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
            guard await playlist.add(itemToAdd) else {
                alertService.showAlert(with: "Couldn’t add to \(playlist.title)", imageName: "exclamationmark.triangle")
                return
            }
            alertService.showAlertContent(with: itemToAdd, subtitle: "Added to \(playlist.title)", symbolName: "plus")

            // Let tapping the toast open the playlist. For Sonos, resolve the real playlist so the
            // detail carries artwork; streaming playlists open from a lightweight stub (the detail
            // view loads them by id).
            let target: PlayableContent?
            if playlist.service == .library {
                target = await sonosService.sonosPlaylists().first(where: { $0.id == playlist.id })
            } else {
                target = playlist.playableContent
            }
            if let target {
                alertService.alert.handleTap = {
                    Router.main.presentedSheet = .mediaDetail(content: target, group: nil)
                }
            }
        }
    }
}
