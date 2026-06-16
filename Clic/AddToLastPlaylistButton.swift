import SwiftUI
import SonosKit
import Defaults

/// One-tap shortcut to add the current item to the most recently used playlist. The icon reflects the
/// destination service (Apple Music / Spotify / Plex / Sonos). For streaming playlists it only appears
/// when the item is from the same service, since you can't add across services.
struct AddToLastPlaylistButton: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(AlertService.self) var alertService: AlertService

    @AppStorage(AppStorageKeys.lastPlaylistID) private var lastPlaylistID: String?
    @AppStorage(AppStorageKeys.lastPlaylistTitle) private var lastPlaylistTitle: String?
    @AppStorage(AppStorageKeys.lastPlaylistService) private var lastPlaylistServiceRaw: String?

    var itemToAdd: PlayableContent

    private var lastService: MusicService {
        MusicService(service: lastPlaylistServiceRaw ?? "library") ?? .library
    }

    /// Streaming playlists can only take tracks from the same service; Sonos accepts anything.
    private var isCompatible: Bool {
        lastService == .library || lastService == itemToAdd.content.service
    }

    var body: some View {
        if let lastPlaylistID, let lastPlaylistTitle, isCompatible {
            Button {
                add(playlistID: lastPlaylistID, title: lastPlaylistTitle)
            } label: {
                Label {
                    Text("Add to \(lastPlaylistTitle)")
                } icon: {
                    icon
                }
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch lastService {
        case .apple, .spotify, .plex:
            lastService.icon
                .frame(width: 20, height: 20)
        default:
            Image(systemName: "text.badge.plus")
        }
    }

    private func add(playlistID: String, title: String) {
        Task {
            alertService.showAlertContent(with: itemToAdd, subtitle: "Added to \(title)", symbolName: "plus")
            switch lastService {
            case .apple:
                _ = await MusicSearchService.shared.addToApplePlaylist(track: itemToAdd, playlistID: playlistID)
            case .spotify:
                _ = await MusicSearchService.shared.addToSpotifyPlaylist(track: itemToAdd, playlistID: playlistID)
            case .plex:
                _ = await MusicSearchService.shared.addToPlexPlaylist(track: itemToAdd, playlistID: playlistID)
            default:
                await sonosService.addToPlaylist(playlistID: playlistID, playableContent: itemToAdd)
                let playlists = await sonosService.sonosPlaylists()
                if let playlist = playlists.first(where: { $0.id == playlistID }) {
                    alertService.alert.handleTap = {
                        Router.main.presentedSheet = .mediaDetail(content: playlist, group: nil)
                    }
                }
            }
        }
    }
}
