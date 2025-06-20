import SwiftUI
import SonosKit
import MusicSearchKit

struct PlayableMenuView: View {
    @Environment(\.dismiss) private var dismiss

    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router
    @Environment(ContentToAdd.self) private var adding: ContentToAdd?
    @Environment(AlertService.self) private var alertService: AlertService
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    var item: PlayableContent

    var body: some View {
        VStack {
            // TODO: Add scene playlist
            //                NavigationLink(value: RouterDestination.createScene(content: item)) {
            //                    Label("Create Scene", systemImage: "bolt.fill")
            //                }
            switch item.content.type {
            case .artistRadio, .songRadio:
                if [.spotify, .apple].contains(item.content.service) {
                    Button {
                        startRadio()
                    } label: {
                        Label("Start Radio", systemImage: "radio.fill")
                    }
                }
            case .artist, .libraryArtist:
                NavigationLink(value: RouterDestination.artistDetail(content: item, group: selectedGroupService.group)) {
                    Label("View Artist", systemImage: "music.mic")
                }

                if [.spotify, .apple].contains(item.content.service) && item.content.type != .libraryArtist {
                    Button {
                        startRadio()
                    } label: {
                        Label("Start Radio", systemImage: "radio.fill")
                    }
                }
            case .playlist, .libraryPlaylist, .libraryImportedPlaylists:
                ControlGroup("Queue \(item.title)") {
                    Button {
                        play(position: .replace)
                    } label: {
                        Label("Replace", systemImage: "play.fill")
                    }

                    Button {
                        play(position: .next)
                    } label: {
                        Label("Play Next", systemImage: "text.insert")
                    }

                    Button {
                        play(position: .end)
                    } label: {
                        Label("Play Last", systemImage: "text.append")
                    }
                    
                    Button {
                        play(position: .replace, shuffle: true)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                }

                if item.content.service == .library, item.content.id.last?.isNumber ?? false {
                    Button {
                        router.sheet(to: .renamePlaylist(content: item))
                    } label: {
                        Label("Rename", systemImage: "textformat")
                    }
                }
            case .album, .track, .libraryTrack, .libraryAlbum:
                ControlGroup("Queue \(item.title)") {
                    Button {
                        play(position: .now)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }

                    Button {
                        play(position: .next)
                    } label: {
                        Label("Play Next", systemImage: "text.insert")
                    }

                    Button {
                        play(position: .end)
                    } label: {
                        Label("Play Last", systemImage: "text.append")
                    }
                }
                
                if [.spotify, .apple].contains(item.content.service), item.content.type == .track {
                    Button {
                        startRadio()
                    } label: {
                        Label("Start Radio", systemImage: "radio.fill")
                    }
                }
                
                if item.content.type == .album {
                    Button {
                        play(position: .replace)
                    } label: {
                        Label("Replace Queue", systemImage: "play.fill")
                    }
                }
                
                if [.album, .track].contains(item.content.type), item.content.service != .unknown {
                    NavigationLink(value: RouterDestination.mediaDetail(content: item, group: selectedGroupService.group)) {
                        Label("View Album", systemImage: "smallcircle.circle.fill")
                    }

                    NavigationLink(value: RouterDestination.artistDetail(content: item, group: selectedGroupService.group)) {
                        Label("View Artist", systemImage: "music.mic")
                    }
                }

                AddToPlaylistMenu(itemToAdd: item)
                // MARK: Add back
//                #if !targetEnvironment(macCatalyst)
//                if item.content.service == .apple {
//                    Button {
//                        Task {
////                            try await AppleMusicAPI().favorite(songId: item.id, favorite: true)
//                            try? await AppleMusicAPI().updateFavoriteStatus(songId: item.id, favorite: true)
////                            isFavorite = try? await AppleMusicAPI().isFavorite(songId: group.coordinatorRoom.track.trackID)
//                        }
//                    } label: {
//                        Label("Favorite in \(item.content.service.title)", systemImage: "heart.fill")
//                    }
//                }
//                #endif
            case .radio, .favorite:
                Button {
                    play()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
            }
        }
        OpenInServiceView(item: item)

        Button {
            selectedGroupService.group = nil
            play()
        } label: {
            Label("Play in Another Room…", systemImage: "hifispeaker.arrow.forward.fill")
        }
        
        if item.content.service == .library, item.content.type == .playlist {
            Button(role: .destructive) {
                Task {
                    await sonosService.delete(playlistID: item.id)
                }
            } label: {
                Label("Delete from Library", systemImage: "trash")
            }
        }
        
        if playHistoryService.history.contains(item) {
            Button(role: .destructive) {
                playHistoryService.history.remove(item)
            } label: {
                Label("Remove from History", systemImage: "trash")
            }
        }
    }

    private func play(position: QueuePosition = .now, shuffle: Bool = false) {
        if let add = adding?.add, add {
            adding?.content = item
            router.dismiss = true
            return
        }
        Task { @MainActor in
            hideKeyboard()
            let queueSong: ((GroupRoom) async throws -> Void) = { group in
                let playMode: PlayMode = shuffle ? [.shuffle, .normal] : [.normal]
                if shuffle {
                    await sonosService.setPlayMode(group.ip, mode: [.normal, .shuffle])
                }
                QueueManager.shared.addToQueue(item: QueueItem(playableContent: item, group: group, position: position, title: position.title, playMode: playMode, showBanner: true))
            }
            guard let group = selectedGroupService.group else {
                router.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onSelection: queueSong, content: item))
                return
            }
            try await queueSong(group)
        }
    }
    
    private func startRadio() {
        Task { @MainActor in
            hideKeyboard()
            let startRadio: ((GroupRoom) async throws -> Void) = { group in
                let radioItem = item.toRadio
                QueueManager.shared.addToQueue(item: QueueItem(playableContent: radioItem, group: group, position: .now, title: "Starting radio", showBanner: true))
            }
            guard let group = selectedGroupService.group else {
                router.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onSelection: startRadio, content: item))
                return
            }
            try await startRadio(group)
        }
    }
}
