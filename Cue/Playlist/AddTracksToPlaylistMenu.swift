import SwiftUI
import SonosKit
import MusicSearchKit

struct AddTracksToPlaylistMenu: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(AlertService.self) private var alertService

    var tracks: [PlayableContent]

    var body: some View {
        Menu {
            Button {
                Task {
                    guard let firstTrack = tracks.first else { return }
                    let playlistTitle = firstTrack.metadata?.artist ?? firstTrack.title
                    await sonosService.createPlaylist(title: playlistTitle)
                    let playLists = await sonosService.sonosPlaylists()
                    guard let newPlaylist = playLists.first(where: { $0.title == playlistTitle }) else { return }
                    
                    for track in tracks {
                        await sonosService.addToPlaylist(playlistID: newPlaylist.id, playableContent: track)
                    }
                    
                    alertService.showAlert(with: "Added \(tracks.count) tracks to \(playlistTitle)", imageName: "plus")
                    playlistsContainer.playlists = playLists
                    
                    LastPlaylist.save(newPlaylist)

                    alertService.alert.handleTap = {
                        MediaDetailPresenter.present(newPlaylist)
                    }
                }
            } label: {
                LabeledContent("Create Playlist") {
                    Image(systemName: "plus")
                }
            }
            ForEach(playlistsContainer.playlists) { playlist in
                Button(playlist.title) {
                    Task {
                        alertService.showAlert(with: "Adding \(tracks.count) tracks…", imageName: "plus")

                        for track in tracks {
                            await sonosService.addToPlaylist(playlistID: playlist.id, playableContent: track)
                        }

                        alertService.showAlert(with: "Added \(tracks.count) tracks to \(playlist.title)", imageName: "checkmark")
                        
                        LastPlaylist.save(playlist)

                        alertService.alert.handleTap = {
                            MediaDetailPresenter.present(playlist)
                        }
                    }
                }
            }
        } label: {
            Label("Add \(tracks.count) to Playlist", systemImage: "text.badge.plus")
                .task {
                    playlistsContainer.playlists = await sonosService.sonosPlaylists()
                }
        }
    }
}
