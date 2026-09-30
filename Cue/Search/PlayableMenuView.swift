import Defaults
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
    @AppStorage(Defaults.AppStorageKeys.defaultPlayAction) private var replaceQueueByDefault: Bool = false
    var item: PlayableContent
    /// When set (track shown inside an editable playlist), adds a "Remove from Playlist" action.
    var onRemoveFromPlaylist: (() -> Void)? = nil

    /// Create Scene and Play in Room… are hidden from this menu for now.
    private static let showsSpeakerShortcuts = false

    var body: some View {
        VStack {
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
                        play(position: .replace, shuffle: true)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }

                    Button {
                        play(position: .next)
                    } label: {
                        Label("Play Next", systemImage: "text.insert")
                    }
                }

                if (item.content.service == .library && item.content.id.last?.isNumber ?? false) || item.isFilesPlaylist {
                    Button {
                        router.sheet(to: .renamePlaylist(content: item))
                    } label: {
                        Label("Rename", systemImage: "textformat")
                    }
                }

                if [.spotify, .plex, .deezer, .subsonic].contains(item.content.service) || item.isFilesPlaylist {
                    Button(role: .destructive) {
                        router.sheet(to: .confirmDeletePlaylist(content: item))
                    } label: {
                        Label("Delete Playlist", systemImage: "trash")
                    }
                }
            case .album, .track, .libraryTrack, .libraryAlbum:
                ControlGroup("Queue \(item.content.type.title)") {
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
                
                if [.spotify, .apple, .deezer, .plex, .subsonic].contains(item.content.service),
                   [.track, .libraryTrack].contains(item.content.type),
                   let previewURL = item.previewURL,
                   !previewURL.absoluteString.isEmpty {
                    SongPreviewButton(previewURL: previewURL, streaming: item.content.service.streamsFullTrackPreview)
                }
                
                if LocalPlaybackService.shared.canPlayAnywhereLocally(item) {
                    Menu {
                        Button {
                            playOnDevice { try await LocalPlaybackService.shared.play(localItems()) }
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }

                        // A station is live: it replaces what's playing and
                        // has no place in a queue behind it.
                        if !item.content.type.isRadio {
                            Button {
                                playOnDevice(subtitle: "Playing next on this device") {
                                    try await LocalPlaybackService.shared.playNext(localItems())
                                }
                            } label: {
                                Label("Play Next", systemImage: "text.insert")
                            }

                            Button {
                                playOnDevice(subtitle: "Added to device queue") {
                                    try await LocalPlaybackService.shared.addToQueue(localItems())
                                }
                            } label: {
                                Label("Add to Queue", systemImage: "text.append")
                            }
                        }

                        if LocalPlaybackService.shared.nowPlaying == item {
                            Button {
                                LocalPlaybackService.shared.stop()
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                        }
                    } label: {
                        Label("This Device", systemImage: "iphone.radiowaves.left.and.right")
                    }

                    // Downloads sit at the top level, not inside the This
                    // Device submenu, so they're one tap away.
                    Section {
                        LocalDownloadMenuSection(item: item)
                    }
                    .onAppear {
                        AppleDownloadsIndex.shared.refreshIfNeeded()
                    }
                }

                if (item.content.service == .apple && [.track, .libraryTrack].contains(item.content.type))
                    || (item.content.service == .spotify && item.content.type == .track) {
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

                Divider()
                AddToLastPlaylistButton(itemToAdd: item)
                if AddToPlaylistSheet.canAdd(item) {
                    Button {
                        router.sheet(to: .addToPlaylist(content: item))
                    } label: {
                        Label("Add to Playlist…", systemImage: "text.badge.plus")
                    }
                }
                Divider()
              
                // Library songs map to a catalog track behind the scenes, so the
                // album/artist we open is the Apple Music catalog version — label
                // it as such to distinguish it from the on-device library album.
                if item.content.type == .libraryTrack, item.content.service == .apple {
                    NavigationLink(value: RouterDestination.mediaDetail(content: item, group: selectedGroupService.group)) {
                        Label("Apple Album", systemImage: "smallcircle.circle.fill")
                    }

                    NavigationLink(value: RouterDestination.artistDetail(content: item, group: selectedGroupService.group)) {
                        Label("Apple Artist", systemImage: "music.mic")
                    }
                }

                if item.content.service.supportsFavoriteTrack, [.track, .libraryTrack].contains(item.content.type) {
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
        
        if Self.showsSpeakerShortcuts, item.content.type != .folder {
            Button {
                router.sheet(to: .createScene(content: item))
            } label: {
                Label("Create Scene", systemImage: "bolt.fill")
            }
        }
        
        if [.spotify, .apple].contains(item.content.service),
           [.album, .libraryAlbum].contains(item.content.type) {
            FavoriteMenuButton(item: item)
        }
        
        OpenInServiceView(item: item)

        if Self.showsSpeakerShortcuts, item.content.type != .folder {
            Button {
                selectedGroupService.group = nil
                play()
            } label: {
                Label("Play in Room…", systemImage: "hifispeaker.arrow.forward.fill")
            }
        }
        
        if item.content.service == .library, item.content.type == .playlist {
            Button(role: .destructive) {
                router.sheet(to: .confirmDeletePlaylist(content: item))
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

        if let onRemoveFromPlaylist {
            Button(role: .destructive) {
                onRemoveFromPlaylist()
            } label: {
                Label("Remove from Playlist", systemImage: "trash")
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
            let queueSong: ((GroupRoom, QueuePosition) async throws -> Void) = { group, selectedPosition in
                if shuffle {
                    await sonosService.setPlayMode(group.ip, mode: [.normal, .shuffle])
                }
                QueueManager.shared.addToQueue(item: QueueItem(playableContent: item, group: group, position: selectedPosition, title: selectedPosition.title, showBanner: true))
            }
            guard let group = selectedGroupService.group else {
                await PlayDestinationRouter.play(item, position: position, shuffle: shuffle, queue: queueSong)
                return
            }
            try await queueSong(group, position)
        }
    }
    
    private func playFolder() {
        Task { @MainActor in
            hideKeyboard()
            let enqueueFolder: ((GroupRoom, QueuePosition) async throws -> Void) = { [self] group, selectedPosition in
                guard let browseService = appleMusicBrowseService else { return }
                let (playlists, _) = await browseService.getPlaylistFolderContents(id: item.id, offset: 0)
                let items = playlists.enumerated().map { index, playlist in
                    QueueItem(playableContent: playlist, group: group, position: index == 0 ? selectedPosition : .end, title: "Playing Folder \(item.title)", showBanner: true)
                }
                QueueManager.shared.add(items: items)
            }
            guard let group = selectedGroupService.group else {
                await PlayDestinationRouter.play(item, position: .replace, queue: enqueueFolder)
                return
            }
            try await enqueueFolder(group, .replace)
        }
    }

    /// The items a local-queue action should operate on: the track itself, or
    /// an album's fetched tracks.
    private func localItems() async throws -> [PlayableContent] {
        if LocalPlaybackService.shared.canPlayLocally(item) { return [item] }
        let tracks = await LocalPlaybackService.shared.containerTracks(for: item)
        guard !tracks.isEmpty else { throw LocalPlaybackService.LocalPlaybackError.nothingPlayable }
        return tracks
    }

    /// Runs a local-playback queue action (play / play next / add to queue) on
    /// this device instead of a Sonos group. Apple tracks need an Apple Music
    /// subscription — failures surface as alerts.
    private func playOnDevice(
        subtitle: LocalizedStringKey = "Playing on this device",
        action: @escaping () async throws -> Void
    ) {
        Task { @MainActor in
            hideKeyboard()
            do {
                try await action()
                alertService.showAlertContent(with: item, subtitle: subtitle, symbolName: "iphone.radiowaves.left.and.right")
            } catch {
                alertService.showAlert(with: error.localizedDescription, imageName: "exclamationmark.triangle")
            }
        }
    }

    private func startRadio() {
        Task { @MainActor in
            hideKeyboard()
            let startRadio: ((GroupRoom) async throws -> Void) = { group in
                guard let radioItem = await resolveRadioSeed(for: item) else { return }
                QueueManager.shared.addToQueue(item: QueueItem(playableContent: radioItem, group: group, position: .now, title: "Starting radio", showBanner: true))
            }
            // A speaker in context plays Sonos' radio. Otherwise the
            // remembered destination decides: a speaker, or Apple Music's
            // station for the song or artist on this device.
            guard let group = selectedGroupService.group else {
                await PlayDestinationRouter.playRadio(from: item, onGroup: startRadio)
                return
            }
            try await startRadio(group)
        }
    }

    /// Builds the radio seed for `content`. Apple library tracks carry a library
    /// ID (`i.…`) that the radio URI can't use, so we first resolve the matching
    /// catalog song ID via the library→catalog relationship and seed the station
    /// from that, falling back to `nil` if no catalog match exists.
    private func resolveRadioSeed(for content: PlayableContent) async -> PlayableContent? {
        guard content.content.type == .libraryTrack, content.content.service == .apple else {
            return content.toRadio
        }
        guard let catalogSong = await MusicSearchService.shared.appleLibraryLookup(id: content.content.id),
              let catalogID = catalogSong.data.first?.id else { return nil }
        let catalogTrack = PlayableContent(
            title: content.title,
            subtitle: content.subtitle,
            thumbnail: content.thumbnail,
            artwork: content.artwork,
            content: MediaContent(service: .apple, id: catalogID, type: .track, location: nil),
            metadata: content.metadata
        )
        return catalogTrack.toRadio
    }
}
