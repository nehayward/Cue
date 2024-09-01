import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import NukeUI
import VibesDS

struct MediaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService
    @Environment(MusicSearchService.self) private var musicSearchService: MusicSearchService

    @State var playableContent: PlayableContent
    @State private var tracks: OrderedSet<PlayableContent> = []
    @State private var artworkURL: URL?
    @State private var isLoaded: Bool = false
    @State private var size: Int?
    @State private var duration: Duration?

    var body: some View {
        List {
            Group {
                LazyImage(url: artworkURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .transition(.opacity)
                    } else if state.isLoading {
                        RoundedRectangle(cornerRadius: 4)
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.ultraThinMaterial)
                            .shadow(radius: 2)
                    } else {
                        Rectangle()
                            .foregroundStyle(.accent.gradient.secondary)
                            .aspectRatio(contentMode: .fit)
                            .overlay {
                                if state.error != nil {
                                    Image(systemName: "music.note")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundStyle(.regularMaterial)
                                        .frame(width: 100, height: 100)
                                }
                            }
                    }
                }
                .transition(.opacity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 2)
                .scaledToFit()
                .overlay(alignment: .bottomTrailing) {
                    playableContent.content.service.icon
                        .frame(width: 24, height: 24, alignment: .trailing)
                        .padding([.bottom, .trailing])
                }
                // TODO: Add back for plex, need to handle image size changes
//                ContentArtworkView(content: playableContent)
//                    .frame(idealWidth: 320, idealHeight: 320)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            VStack {
                Text("\(playableContent.subtitle)")
                HStack(spacing: 0) {
                    if let size {
                        Text(size, format: .number)
                    } else {
                        Text("\(tracks.count.formatted())")
                    }
                    Text(" Tracks")
                    if let duration {
                        Text(" • \(duration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))")
                    } else {
                        if totalDuration.components.seconds > 0  {
                            Text(" • \(totalDuration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .fontDesign(.rounded)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            HStack {
                Button {
                    play(replaceQueue: true)
                } label: {
                    Text("Replace")
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundStyle(.foreground)
                }
                .bold()
                .buttonStyle(.bordered)
                .tint(.accent)

                Button {
                    play(position: .next)
                } label: {
                    Text("Play Next")
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundStyle(.foreground)
                }
                .bold()
                .buttonStyle(.bordered)
                .tint(.accent)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            ForEach(tracks) { item in
                PlayableContentView(item: item, hideArtwork: playableContent.content.type == .album)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                guard let index = tracks.firstIndex(where: { $0 == item }) else { return }
                                try await sonosService.removeTrackFromPlaylist(playlistID: playableContent.id, index: index)
                                tracks.remove(at: index)
                            }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .disabled(!(item.metadata?.isPlayable ?? true))
                    .task {
                        if tracks.firstIndex(of: item) ?? 0 >= tracks.count - 1 {
                            Task {
                                await updateTracks(offset: tracks.count)
                            }
                        }
                    }
            }

            if tracks.isEmpty, !isLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .task {
            await updateTracks()
        }
        .listStyle(.plain)
        .contentMargins(.bottom, 80, for: .scrollContent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(playableContent.title)
                    .fontDesign(.rounded)
                    .bold()
                    .multilineTextAlignment(.center)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    PlayableMenuView(item: playableContent)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(maxWidth: 40, maxHeight: .infinity)
                        .background(.clear)
                        .bold()
                        .foregroundStyle(.foreground)
                }
            }
        }
    }

    private func play(position: QueuePosition = .now, replaceQueue: Bool = false) {
        Task { @MainActor in
            hideKeyboard()
            let queueSong: ((GroupRoom) async -> Void) = { group in
                playHistoryService.history.remove(playableContent)
                playHistoryService.history.insert(playableContent, at: 0)
                HapticManager.shared.fireHaptic(.buttonPress)
                await sonosService.setPlayMode(group.ip, mode: [.normal])
                await sonosService.queue(playable: playableContent, group: group, position: position, replaceQueue: replaceQueue)
                await sonosService.play(ip: group.coordinatorRoom.ip)
            }
            guard let group = selectedGroupService.group else {
                router.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onSelection: queueSong))
                return
            }
            await queueSong(group)
        }
    }

    private var totalDuration: Duration {
        Duration.seconds(tracks.compactMap(\.metadata?.duration?.components.seconds).reduce(Int64.zero, +))
    }

    private func updateTracks(offset: Int = 0) async {
        isLoaded = false
        var newTracks: [PlayableContent] = []
        // TODO: Refactor into MusicService
        artworkURL = playableContent.artwork
        switch (playableContent.content.type, playableContent.content.service) {
        case (.album, .apple):
            guard let album: Album = try? await musicSearchService.lookup(id: playableContent.content.id) else { return }
            artworkURL = album.artwork?.url(width: 800, height: 800)
            guard let tracks = album.tracks else { return }
            newTracks = tracks.map(\.toPlayable)
        case (.libraryAlbum, .apple):
            artworkURL = playableContent.artwork
            if let album = await musicSearchService.appleLibraryAlbum(id: playableContent.id) {
                artworkURL = album.data.first?.attributes.artwork?.urlWithSize(width: 500, height: 500)
            }
            newTracks = await AppleMusicBrowseService.shared.albumLookup(id: playableContent.id)
        case (.album, .spotify):
            guard let albumDetails = await musicSearchService.spotifyAlbumTracksLookup(id: playableContent.content.id) else { return }
            newTracks = albumDetails.tracks.items.map { $0.toPlayable(artwork: albumDetails.images.thumbnail) }
        case (.playlist, .apple):
            guard let playlist: Playlist = try? await musicSearchService.lookup(id: playableContent.content.id) else { return }
            artworkURL = playlist.artwork?.url(width: 800, height: 800)
            guard let tracks = playlist.tracks else { return }
            newTracks = tracks.map(\.toPlayable)
        case (.libraryPlaylist, .apple):
            artworkURL = playableContent.artwork
            let (tracks, playlistCount) = await AppleMusicBrowseService.shared.tracksForUserPlaylists(id: playableContent.id, offset: offset)
            newTracks = tracks
            size = playlistCount
        case (.playlist, .spotify):
            guard let playlist = await musicSearchService.spotifyPlaylistTracks(id: playableContent.content.id, offset: offset) else { return }
            size = playlist.total
            newTracks = playlist.items.map { $0.track.toPlayable(artwork: $0.track.album?.images.thumbnail)}
        case (.track, .apple):
            guard let song: Song = try? await musicSearchService.lookup(id: playableContent.content.id), let albumID = song.albums?.first?.id.description else { return }
            guard let album: Album = try? await musicSearchService.lookup(id: albumID) else { return }
            artworkURL = album.artwork?.url(width: 800, height: 800)
            playableContent = album.toPlayable
            guard let tracks = album.tracks else { return }
            newTracks = tracks.map(\.toPlayable)
        case (.libraryTrack, .apple):
            guard let catalogSong = await musicSearchService.appleLibraryLookup(id: playableContent.content.id), let id = catalogSong.data.first?.id else { return }
            guard let song: Song = try? await musicSearchService.lookup(id: id), let albumID = song.albums?.first?.id.description else { return }
            guard let album: Album = try? await musicSearchService.lookup(id: albumID) else { return }
            artworkURL = album.artwork?.url(width: 800, height: 800)
            playableContent = album.toPlayable
            guard let tracks = album.tracks else { return }
            newTracks = tracks.map(\.toPlayable)
        case (.track, .spotify):
            guard let song = await musicSearchService.spotifyTrackLookup(id: playableContent.content.id) else { return }
            guard let albumDetails = await musicSearchService.spotifyAlbumTracksLookup(id: song.album.id) else { return }
            playableContent = albumDetails.toPlayable
            artworkURL = albumDetails.images.biggestImageURL
            newTracks = albumDetails.tracks.items.map { $0.toPlayable(artwork: albumDetails.images.thumbnail) }
        case (.album, .library):
            artworkURL = playableContent.artwork
            newTracks = await sonosService.libraryLookup(ID: playableContent.id)
        case (.playlist, .library):
            artworkURL = playableContent.artwork
            newTracks = await sonosService.sonosPlaylistsTracks(for: playableContent.id)
        case (.track, .library):
            artworkURL = playableContent.artwork
            guard let albumName = playableContent.metadata?.album,
                  let albumNameEncoded = albumName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }

            newTracks = await sonosService.libraryAlbum(name: albumName)
            guard let albumPlayable =  await sonosService.libraryLookup(ID: "A:ALBUM:\(albumNameEncoded)").first else { return }
            playableContent = albumPlayable
        case (.album, .tidal):
            newTracks = await musicSearchService.lookupTidalAlbumTracks(id: playableContent.content.id)
        case (.track, .tidal):
            if let albumID = playableContent.metadata?.albumID {
                guard let album = await musicSearchService.lookupTidalAlbum(with: albumID) else { return }
                newTracks = await musicSearchService.lookupTidalAlbumTracks(id: albumID)
                playableContent = album
                artworkURL = playableContent.artwork
            } else {
                guard let albumID = await musicSearchService.lookupTidalTrack(with: playableContent.id)?.metadata?.albumID else { return }
                guard let album = await musicSearchService.lookupTidalAlbum(with: albumID) else { return }
                newTracks = await musicSearchService.lookupTidalAlbumTracks(id: albumID)
                playableContent = album
                artworkURL = playableContent.artwork
            }
            // MARK: Plex
        case (.track, .plex):
            if let albumID = playableContent.metadata?.albumID {
                guard let album = await musicSearchService.lookupPlexAlbum(id: albumID) else { return }
                playableContent = album
                newTracks = await musicSearchService.lookupPlexAlbumSongs(id: albumID)
            } else {
                guard let id = playableContent.id.removingPercentEncoding?.components(separatedBy: ":").last,
                      let albumID = await musicSearchService.lookupPlexSong(with: id)?.metadata?.albumID,
                      let album = await musicSearchService.lookupPlexAlbum(id: albumID) else { return }
                playableContent = album
                newTracks = await musicSearchService.lookupPlexAlbumSongs(id: albumID)
            }
        case (.album, .plex):
            newTracks = await musicSearchService.lookupPlexAlbumSongs(id: playableContent.content.id)
        case (.playlist, .plex):
            (size, newTracks, duration) = await musicSearchService.lookupPlexPlaylists(id: playableContent.content.id, offset: offset)
        default:
            break
        }
        for newTrack in newTracks {
            tracks.updateOrAppend(newTrack)
        }
        isLoaded = true
    }

    // TODO: Add later
//    private func move(from source: IndexSet, to destination: Int) {
//        // TODO: Fix swap positions
//        tracks.move(fromOffsets: source, toOffset: destination)
//
//        Task {
//            guard let sourceIndex = source.first else { return }
//            try await sonosService.reorderPlaylist(playlistID: playableContent.id, from: sourceIndex + 1, to: destination + 1)
//        }
//    }

}



//#Preview {
//    // https://music.apple.com/us/playlist/dua-lipa-essentials/pl.ee7b1aea4b5f42d398e6cd3084f7396b
//    // https://music.apple.com/us/album/future-nostalgia-the-moonlight-edition/1551178998
//    MediaDetailView(id: "1552269067", title: "Future Nostaliga", kind: .album)
//        .environment(SonosService.shared)
//        .environment(Router())
//}
