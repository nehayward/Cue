import SwiftUI
import UIKit
import SonosKit
import MusicSearchKit
import Defaults

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
                    
                    UserDefaults.standard.set(newPlaylist.id, forKey: AppStorageKeys.lastPlaylistID)
                    UserDefaults.standard.set(newPlaylist.title, forKey: AppStorageKeys.lastPlaylistTitle)
#if targetEnvironment(macCatalyst)
                    UIMenuSystem.main.setNeedsRebuild()
#endif
                    
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
                        alertService.showAlert(with: "Adding \(tracks.count) tracks…", imageName: "plus")
                        
                        for track in tracks {
                            await sonosService.addToPlaylist(playlistID: playlist.id, playableContent: track)
                        }
                        
                        alertService.showAlert(with: "Added \(tracks.count) tracks to \(playlist.title)", imageName: "checkmark")
                        
                        UserDefaults.standard.set(playlist.id, forKey: AppStorageKeys.lastPlaylistID)
                        UserDefaults.standard.set(playlist.title, forKey: AppStorageKeys.lastPlaylistTitle)
#if targetEnvironment(macCatalyst)
                        UIMenuSystem.main.setNeedsRebuild()
#endif
                        
                        alertService.alert.handleTap = {
                            Router.main.presentedSheet = .mediaDetail(content: playlist, group: nil)
                        }
                    }
                }
            }
        } label: {
            Label("Add Popular to Playlist", systemImage: "text.badge.plus")
                .task {
                    playlistsContainer.playlists = await sonosService.sonosPlaylists()
                }
        }
    }
}

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
