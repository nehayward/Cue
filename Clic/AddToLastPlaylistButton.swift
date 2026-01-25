import SwiftUI
import SonosKit
import Defaults

struct AddToLastPlaylistButton: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(AlertService.self) var alertService: AlertService

    @AppStorage(AppStorageKeys.lastPlaylistID) private var lastPlaylistID: String?
    @AppStorage(AppStorageKeys.lastPlaylistTitle) private var lastPlaylistTitle: String?

    var itemToAdd: PlayableContent

    var body: some View {
        if let lastPlaylistID, let lastPlaylistTitle {
            Button {
                Task {
                    alertService.showAlertContent(with: itemToAdd, subtitle: "Added to \(lastPlaylistTitle)", symbolName: "plus")
                    await sonosService.addToPlaylist(playlistID: lastPlaylistID, playableContent: itemToAdd)

                    // Set up tap to navigate to playlist
                    let playlists = await sonosService.sonosPlaylists()
                    if let playlist = playlists.first(where: { $0.id == lastPlaylistID }) {
                        alertService.alert.handleTap = {
                            Router.main.presentedSheet = .mediaDetail(content: playlist, group: nil)
                        }
                    }
                }
            } label: {
                Label("Add to \(lastPlaylistTitle)", systemImage: "text.badge.plus")
            }
        }
    }
}
