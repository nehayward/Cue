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
    @Environment(AppleMusicBrowseService.self) private var appleMusicBrowseService: AppleMusicBrowseService?
    @Environment(AudioPlaybackService.self) private var audioService: AudioPlaybackService

    var item: PlayableContent

    var body: some View {
        VStack {
            if item.content.type != .folder {
                Button {
                    router.sheet(to: .createScene(content: item))
                } label: {
                    Label("Create Scene", systemImage: "bolt.fill")
                }
            }
            switch item.content.type {
            case .artistRadio, .songRadio:
                if [.spotify, .apple].contains(item.content.service) {
                    Button {
                        startRadio()
                    } label: {
                        Label("Play Radio", systemImage: "dot.radiowaves.left.and.right")
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
                        Label("Play Radio", systemImage: "dot.radiowaves.left.and.right")
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
                if [.spotify, .apple].contains(item.content.service),
                   [.track, .libraryTrack].contains(item.content.type),
                   let previewURL = item.previewURL,
                   !previewURL.absoluteString.isEmpty {
                    SongPreviewButton(previewURL: previewURL)
                }

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
                        Label("Play Radio", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
                
                if ![.track, .libraryTrack].contains(item.content.type) {
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

                AddToLastPlaylistButton(itemToAdd: item)
                AddToPlaylistMenu(itemToAdd: item)

                if [.spotify, .soundcloud, .apple, .plex].contains(item.content.service), [.track, .libraryTrack].contains(item.content.type) {
                    FavoriteMenuButton(item: item)
                }
            case .folder:
                Button {
                    playFolder()
                } label: {
                    Label("Play All Playlists in Folder", systemImage: "play.fill")
                }
            case .radio, .liveRadio, .favorite, .unique:
                Button {
                    play()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
            }
        }
        
        if [.spotify, .apple].contains(item.content.service),
           [.album, .libraryAlbum].contains(item.content.type) {
            FavoriteMenuButton(item: item)
        }
        
        OpenInServiceView(item: item)
            .onDisappear {
                audioService.stopPreview()
            }

        if item.content.type != .folder {
            Button {
                selectedGroupService.group = nil
                play()
            } label: {
                Label("Move to Room…", systemImage: "hifispeaker.arrow.forward.fill")
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
                if shuffle {
                    await sonosService.setPlayMode(group.ip, mode: [.normal, .shuffle])
                }
                QueueManager.shared.addToQueue(item: QueueItem(playableContent: item, group: group, position: position, title: position.title, showBanner: true))
            }
            guard let group = selectedGroupService.group else {
                router.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onSelection: queueSong, content: item))
                return
            }
            try await queueSong(group)
        }
    }
    
    private func playFolder() {
        Task { @MainActor in
            hideKeyboard()
            let enqueueFolder: ((GroupRoom) async throws -> Void) = { [self] group in
                guard let browseService = appleMusicBrowseService else { return }
                let (playlists, _) = await browseService.getPlaylistFolderContents(id: item.id, offset: 0)
                let items = playlists.enumerated().map { index, playlist in
                    QueueItem(playableContent: playlist, group: group, position: index == 0 ? .replace : .end, title: "Playing Folder \(item.title)", showBanner: true)
                }
                QueueManager.shared.add(items: items)
            }
            guard let group = selectedGroupService.group else {
                router.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onSelection: enqueueFolder, content: item))
                return
            }
            try await enqueueFolder(group)
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
