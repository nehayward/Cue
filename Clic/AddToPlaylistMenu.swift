import SwiftUI
import SonosKit
import MusicSearchKit

struct AddToPlaylistMenu: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(AlertService.self) private var alertService

    var itemToAdd: PlayableContent

    var body: some View {
        Menu {
            Group {
                Button {
                    Task {
                        await sonosService.createPlaylist(title: itemToAdd.title)
                        let playLists = await sonosService.sonosPlaylists()
                        guard let id = playLists.first(where: { $0.title == itemToAdd.title })?.id else { return }
                        await sonosService.addToPlaylist(playlistID: id, playableContent: itemToAdd)
                        playlistsContainer.playlists = await sonosService.sonosPlaylists()
                    }
                } label: {
                    LabeledContent("Create Playlist") {
                        Image(systemName: "plus")
                    }
                }
                ForEach(playlistsContainer.playlists) { playlist in
                    Button(playlist.title) {
                        Task {
                            alertService.showAlertContent(with: itemToAdd, subtitle: "Added to \(playlist.title)", symbolName: "plus")
                            await sonosService.addToPlaylist(playlistID: playlist.id, playableContent: itemToAdd)
                        }
                    }
                }
            }
            .task {
                playlistsContainer.playlists = await sonosService.sonosPlaylists()
            }
        } label: {
            Label("Add to Sonos Playlist…", systemImage: "plus")
        }
    }
}
