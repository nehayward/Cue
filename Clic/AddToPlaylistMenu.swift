import SwiftUI
import SonosKit
import MusicSearchKit

struct AddToPlaylistMenu: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer

    var itemToAdd: PlayableContent

    var body: some View {
        Menu {
            ForEach(playlistsContainer.playlists) { playlist in
                Button(playlist.title) {
                    Task {
                        await sonosService.addToPlaylist(playlistID: playlist.id, playableContent: itemToAdd)
                    }
                }
            }
        } label: {
            Label("Add to Playlist", systemImage: "plus")
        }
    }
}
