import SwiftUI
import UIKit
import SonosKit
import MusicSearchKit
import Defaults

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
                        guard let newPlaylist = playLists.first(where: { $0.title == itemToAdd.title }) else { return }
                        await sonosService.addToPlaylist(playlistID: newPlaylist.id, playableContent: itemToAdd)
                        alertService.showAlertContent(with: itemToAdd, subtitle: "Created \(itemToAdd.title)", symbolName: "plus")
                        playlistsContainer.playlists = playLists

                        // Save as last used playlist and rebuild menu
                        UserDefaults.standard.set(newPlaylist.id, forKey: AppStorageKeys.lastPlaylistID)
                        UserDefaults.standard.set(newPlaylist.title, forKey: AppStorageKeys.lastPlaylistTitle)
                        #if targetEnvironment(macCatalyst)
                        UIMenuSystem.main.setNeedsRebuild()
                        #endif

                        // Set up tap to navigate to playlist
                        alertService.alert.handleTap = {
                            Router.main.presentedSheet = .mediaDetail(content: newPlaylist, group: nil)
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
                            alertService.showAlertContent(with: itemToAdd, subtitle: "Added to \(playlist.title)", symbolName: "plus")
                            await sonosService.addToPlaylist(playlistID: playlist.id, playableContent: itemToAdd)

                            // Save as last used playlist and rebuild menu
                            UserDefaults.standard.set(playlist.id, forKey: AppStorageKeys.lastPlaylistID)
                            UserDefaults.standard.set(playlist.title, forKey: AppStorageKeys.lastPlaylistTitle)
                            #if targetEnvironment(macCatalyst)
                            UIMenuSystem.main.setNeedsRebuild()
                            #endif

                            // Set up tap to navigate to playlist
                            alertService.alert.handleTap = {
                                Router.main.presentedSheet = .mediaDetail(content: playlist, group: nil)
                            }
                        }
                    }
                }
            }
            .task {
                playlistsContainer.playlists = await sonosService.sonosPlaylists()
            }
        } label: {
            Label("Add to Playlist", systemImage: "plus")
        }
    }
}
