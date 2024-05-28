import SwiftUI
import SonosKit
import MusicSearchKit

struct AddToPlaylistMenu: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router

    var itemToAdd: PlayableContent
    @State private var playlists: [PlayableContent] = []

    var body: some View {
        Menu("Add to Playlist") {
            ForEach(playlists) { playlist in
                Button(playlist.title) {
                    Task {
                        await sonosService.addToPlaylist(playlistID: playlist.id, playableContent: itemToAdd)
                    }
                }
            }
        }
        .task {
            playlists = await sonosService.sonosPlaylists()
        }
    }
}
