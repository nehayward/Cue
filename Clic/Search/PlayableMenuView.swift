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
            if playHistoryService.history.contains(item) {
                Button(role: .destructive) {
                    playHistoryService.history.remove(item)
                } label: {
                    Label("Remove from History", systemImage: "trash")
                }
            }
            OpenInServiceView(item: item)
            switch item.content.type {
            case .artist, .libraryArtist:
                NavigationLink(value: RouterDestination.artistDetail(content: item, group: selectedGroupService.group)) {
                    Label("View Artist", systemImage: "music.mic")
                }

                if [.spotify, .apple].contains(item.content.service) && item.content.type != .libraryArtist {
                    Button {
                        guard let group = selectedGroupService.group else { return }
                        Task {
                            HapticManager.shared.fireHaptic(.buttonPress)
                            await sonosService.startRadio(content: item, group: group)
                        }
                    } label: {
                        Label("Start Radio", systemImage: "radio.fill")
                    }
                }
            case .playlist, .libraryPlaylist:
                ControlGroup("Queue") {
                    Button {
                        play(replaceQueue: true)
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
                }

                if item.content.service == .library, item.content.id.last?.isNumber ?? false {
                    Button {
                        router.sheet(to: .renamePlaylist(content: item))
                    } label: {
                        Label("Rename", systemImage: "textformat")
                    }
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
// TODO: Add scene playlist
//                NavigationLink(value: RouterDestination.createScene(content: item)) {
//                    Label("Create Scene", systemImage: "bolt.fill")
//                }

            case .album, .track, .libraryTrack, .libraryAlbum:
                if [.album, .track].contains(item.content.type) {
                    NavigationLink(value: RouterDestination.mediaDetail(content: item, group: selectedGroupService.group)) {
                        Label("View Album", systemImage: "smallcircle.circle.fill")
                    }

                    NavigationLink(value: RouterDestination.artistDetail(content: item, group: selectedGroupService.group)) {
                        Label("View Artist", systemImage: "music.mic")
                    }
                }

                ControlGroup("Queue") {
                    if item.content.type == .album {
                        Button {
                            play(replaceQueue: true)
                        } label: {
                            Label("Replace", systemImage: "play.fill")
                        }
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

                AddToPlaylistMenu(itemToAdd: item)
                
                if item.content.service == .apple {
                    Button {
                        Task {
                            try await AppleMusicAPI().favoriteSong(songId: item.id)
                        }
                    } label: {
                        Label("Favorite", systemImage: "play.fill")
                    }
                }
            case .radio, .favorite:
                Button {
                    play()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
            }
        }
    }

    private func play(position: QueuePosition = .now, replaceQueue: Bool = false) {
        if let add = adding?.add, add {
            adding?.content = item
            router.dismiss = true
            return
        }
        Task { @MainActor in
            hideKeyboard()
            let queueSong: ((GroupRoom) async throws -> Void) = { group in
                do {
                    try await sonosService.queue(playable: item, group: group, position: position, replaceQueue: replaceQueue)
                    await sonosService.play(ip: group.coordinatorRoom.ip)
                    playHistoryService.history.remove(item)
                    playHistoryService.history.insert(item, at: 0)
                } catch {
                    alertService.showAlert(with: "Please authorize \(item.content.service.title) in Sonos", imageName: "exclamationmark.triangle.fill")
                }
            }
            guard let group = selectedGroupService.group else {
                router.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onSelection: queueSong))
                return
            }
            try await queueSong(group)
        }
    }
}
