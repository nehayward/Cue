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

    @State var playableContent: PlayableContent
    @State private var tracks: [PlayableContent] = []
    @State private var artworkURL: URL?
    @State private var isLoaded: Bool = false

    private let musicSearchService = MusicSearchService()

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
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 2)
                .scaledToFit()
                .frame(idealWidth: 320, idealHeight: 320)
                .overlay(alignment: .bottomTrailing) {
                    playableContent.content.service.icon
                        .frame(width: 24, height: 24, alignment: .trailing)
                        .padding([.bottom, .trailing])
                }
                // TODO: Add back for plex, need to handle image size changes
//                ContentArtworkView(content: playableContent)
//                    .frame(idealWidth: 320, idealHeight: 320)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            HStack(spacing: 0) {
                Text("\(playableContent.subtitle)\(playableContent.subtitle.isEmpty ? "" : " • ")\(tracks.count.formatted()) Tracks\(totalDuration.components.seconds > 0 ? " • " : "")")
                if totalDuration.components.seconds > 0  {
                    Text(totalDuration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                }
            }
            .frame(maxWidth: .infinity)
            .fontDesign(.rounded)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            HStack {
                Button {
                    play(content: playableContent)
                } label: {
                    Label("Queue All", systemImage: "play.fill")
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
            .overlay(alignment: .trailing) {
                Menu {
                    menu(content: playableContent)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(maxWidth: 40, maxHeight: .infinity)
                        .background(.clear)
                        .bold()
                        .foregroundStyle(.foreground)
                }
            }

            ForEach(tracks) { item in
                PlayableContentView(item: item, hideArtwork: playableContent.content.type == .album)
            }

            if tracks.isEmpty, !isLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, 80, for: .scrollContent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if !isLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    Text(playableContent.title)
                        .fontDesign(.rounded)
                        .bold()
                }
            }
        }
        .task {
            // TODO: Refactor into MusicService
            artworkURL = playableContent.artwork
            switch (playableContent.content.type, playableContent.content.service) {
            case (.album, .apple):
                guard let album: Album = try? await MusicSearchService().lookup(id: playableContent.content.id) else { return }
                artworkURL = album.artwork?.url(width: 800, height: 800)
                guard let tracks = album.tracks else { return }
                self.tracks = tracks.map(\.toPlayable)
            case (.album, .spotify):
                guard let albumDetails = await MusicSearchService().spotifyAlbumTracksLookup(id: playableContent.content.id) else { return }
                self.tracks = albumDetails.tracks.items.map { $0.toPlayable(artwork: albumDetails.images.thumbnail) }
            case (.playlist, .apple):
                guard let playlist: Playlist = try? await MusicSearchService().lookup(id: playableContent.content.id) else { return }
                artworkURL = playlist.artwork?.url(width: 800, height: 800)
                guard let tracks = playlist.tracks else { return }
                self.tracks = tracks.map(\.toPlayable)
            case (.userPlaylist, .apple):
                self.tracks = await musicSearchService.tracksForUserPlaylists(id: playableContent.id)
            case (.playlist, .spotify):
                guard let playlist: SpotifyPlaylistItems = await MusicSearchService().spotifyPlaylistLookup(id: playableContent.content.id) else { return }
                guard let items = playlist.tracks.items else { return }
                self.tracks = items.map { $0.track.toPlayable(artwork: $0.track.album?.images.thumbnail)}
            case (.track, .apple):
                guard let song: Song = try? await MusicSearchService().lookup(id: playableContent.content.id), let albumID = song.albums?.first?.id.description else { return }
                guard let album: Album = try? await MusicSearchService().lookup(id: albumID) else { return }
                artworkURL = album.artwork?.url(width: 800, height: 800)
                playableContent = album.toPlayable
                guard let tracks = album.tracks else { return }
                self.tracks = tracks.map(\.toPlayable)
            case (.track, .spotify):
                guard let song = await MusicSearchService().spotifyTrackLookup(id: playableContent.content.id) else { return }
                guard let albumDetails = await MusicSearchService().spotifyAlbumTracksLookup(id: song.album.id) else { return }
                playableContent = albumDetails.toPlayable
                artworkURL = albumDetails.images.biggestImageURL
                self.tracks = albumDetails.tracks.items.map { $0.toPlayable(artwork: albumDetails.images.thumbnail) }
            case (.album, .library):
                artworkURL = playableContent.artwork
                self.tracks = await sonosService.libraryLookup(ID: playableContent.id)
            case (.playlist, .library):
                artworkURL = playableContent.artwork
                self.tracks = await sonosService.sonosPlaylistsTracks(for: playableContent.id)
            case (.track, .library):
                artworkURL = playableContent.artwork
                guard let albumName = playableContent.metadata?.album,
                      let albumNameEncoded = albumName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }

                self.tracks = await sonosService.libraryAlbum(name: albumName)
                guard let albumPlayable =  await sonosService.libraryLookup(ID: "A:ALBUM:\(albumNameEncoded)").first else { return }
                playableContent = albumPlayable
            case (.album, .tidal):
                self.tracks = await MusicSearchService().lookupTidalAlbumTracks(id: playableContent.content.id)
            case (.track, .tidal):
                if let albumID = playableContent.metadata?.albumID {
                    guard let album = await MusicSearchService().lookupTidalAlbum(with: albumID) else { return }
                    self.tracks = await MusicSearchService().lookupTidalAlbumTracks(id: albumID)
                    playableContent = album
                } else {
                    guard let albumID = await MusicSearchService().lookupTidalTrack(with: playableContent.id)?.metadata?.albumID else { return }
                    guard let album = await MusicSearchService().lookupTidalAlbum(with: albumID) else { return }
                    self.tracks = await MusicSearchService().lookupTidalAlbumTracks(id: albumID)
                    playableContent = album
                }
            case (.album, .plex):
                self.tracks = await MusicSearchService().lookupPlexAlbumSongs(id: playableContent.content.id)
            case (.playlist, .plex):
                self.tracks = await MusicSearchService().lookupPlexPlaylists(id: playableContent.content.id)
            default:
                break
            }
            isLoaded = true
        }
    }

    private func play(content: PlayableContent, position: QueuePosition = .now, replaceQueue: Bool = false) {
        Task { @MainActor in
            guard let group = selectedGroupService.group else {
                router.navigate(to: .groupDestination(content: content, position: position))
                return
            }

            playHistoryService.history.remove(content)
            playHistoryService.history.insert(content, at: 0)

            if replaceQueue {
                try? await sonosService.clearQueue(group.ip)
            }
            HapticManager.shared.fireHaptic(.buttonPress)
            await sonosService.setPlayMode(group.ip, mode: [.normal])
            await sonosService.queue(playable: content, group: group, position: position)
            await sonosService.play(ip: group.coordinatorRoom.ip)
        }
    }

    private func menu(content: PlayableContent) -> some View {
        VStack {
            Button {
                play(content: content, position: .next)
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                play(content: content, position: .end)
            } label: {
                Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
            }

            if playableContent.content.type == .playlist, playableContent.content.service == .library {
                Button(role: .destructive) {
                    Task {
                        guard let index = tracks.firstIndex(where: { $0 == content }) else { return }
                        try await sonosService.removeTrackFromPlaylist(playlistID: playableContent.id, index: index)
                        tracks.remove(at: index)
                    }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }

//            if content.content.type == .album {
//                Button {
//                    play(content: content, position: .front, replaceQueue: true)
//                } label: {
//                    Text("Replace Queue")
//                }
//            }
        }
    }

    private var totalDuration: Duration {
        Duration.seconds(tracks.compactMap(\.metadata?.duration?.components.seconds).reduce(Int64.zero, +))
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
