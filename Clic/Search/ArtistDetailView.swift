import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import NukeUI
import VibesDS

struct ArtistDetailView: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router: Router?
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    @State var playableContent: PlayableContent
    @State private var tracks: [PlayableContent] = []
    @State private var albums: [PlayableContent] = []
    @State private var artworkURL: URL?
    @State private var isLoading: Bool = false


    var body: some View {
        List {
            if artworkURL != nil  {
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
                .clipShape(Circle())
                .shadow(radius: 2)
                .scaledToFit()
                .frame(width: 200, height: 200)
                .frame(maxWidth: .infinity)
                .listSectionSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if [.spotify, .apple].contains(playableContent.content.service) && playableContent.content.type != .libraryArtist {
                HStack {
                    Button {
                        Task {
                            guard let group = selectedGroupService.group else {
                                router?.presentedSheet = .selectGroup(selectedGroupService: selectedGroupService)
                                return
                            }
                            HapticManager.shared.fireHaptic(.buttonPress)
                            await sonosService.startRadio(content: playableContent, group: group)
                        }
                    } label: {
                        Label("Start Radio \(Image(systemName: "radio"))", systemImage: "play.fill")
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
            }

            // TODO: Add Later
//            if [.plex].contains(playableContent.content.service) {
//                HStack {
//                    Button {
//                        Task {
//                            guard let group = selectedGroupService.group else {
//                                router?.presentedSheet = .selectGroup(selectedGroupService: selectedGroupService)
//                                return
//                            }
//                            HapticManager.shared.fireHaptic(.buttonPress)
//                            await sonosService.startRadio(content: playableContent, group: group)
//                        }
//                    } label: {
//                        Label("Popular Tracks", systemImage: "play.fill")
//                            .padding()
//                            .frame(maxWidth: .infinity, alignment: .center)
//                            .foregroundStyle(.foreground)
//                    }
//                    .bold()
//                    .buttonStyle(.bordered)
//                    .tint(.accent)
//                }
//                .frame(maxWidth: .infinity)
//                .listRowBackground(Color.clear)
//                .listRowSeparator(.hidden)
//            }

            if !tracks.isEmpty {
                Section("Top Tracks") {
                    ForEach(tracks) { track in
                        PlayableContentView(item: track)
                    }
                }
            }

            Section("Albums") {
                ForEach(albums) { album in
                    PlayableContentView(item: album)
                }
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }

            //            Section {
            //                ForEach(tracks) { track in
            //                   PlayableContentView(item: track, group: group)
            //                }
            //                if tracks.isEmpty {
            //                    ProgressView()
            //                        .frame(maxWidth: .infinity, alignment: .center)
            //                        .listRowSeparator(.hidden)
            //                }
            //                ForEach(albums) { album in
            //                    PlayableContentView(item: album, group: group)
            //                }
            //                if tracks.isEmpty {
            //                    ProgressView()
            //                        .frame(maxWidth: .infinity, alignment: .center)
            //                        .listRowSeparator(.hidden)
            //                }
            //            } header: {
            // MARK: Add back when queue multiple songs
            //                Button {
            //                    play(content: playableContent)
            //                } label: {
            //                    Text("Play Artist Top Tracks")
            //                }
            //                .padding()
            //                .background(
            //                    .ultraThinMaterial,
            //                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            //                )
            //                .padding(.vertical)
            //                .frame(maxWidth: .infinity, alignment: .center)
            //            }
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .navigationTitle(playableContent.title)
        .headerProminence(.increased)
        .contentMargins(.bottom, 80, for: .scrollContent)
        .task {
            isLoading = true
            artworkURL = playableContent.artwork
            switch (playableContent.content.type, playableContent.content.service) {
            case (.artist, .apple):
                guard let artist: Artist = try? await MusicSearchService().lookup(id: playableContent.content.id) else { return }
                guard let topTracks = artist.topSongs, let albums = artist.albums else { return }
                self.tracks = topTracks.map(\.toPlayable)
                self.albums = albums.map(\.toPlayable)
                artworkURL = artist.artwork?.url(width: 500, height: 500)
            case (.libraryArtist, .apple):
                if let url = await MusicSearchService().appleLibraryArtistArtwork(name: playableContent.title) {
                    artworkURL = url
                }
                if let albums = await MusicSearchService().appleLibraryArtistAlbumLookup(id: playableContent.content.id) {
                    self.albums = albums.data.compactMap(\.toPlayable)
                }
            case (.artist, .spotify):
                async let artist = MusicSearchService().spotifyArtist(id: playableContent.content.id)
                async let artistAlbums = MusicSearchService().spotifyArtistAlbums(id: playableContent.content.id)
                async let artistTopTracks = MusicSearchService().spotifyArtistTopTracks(id: playableContent.content.id)

                guard let artistAwait = await artist else { return }
                guard let artistAlbumsAwait = await artistAlbums else { return }
                let artistTopTracksAwait = await artistTopTracks

                playableContent = artistAwait.toPlayable
                albums = artistAlbumsAwait.items.map(\.toPlayable)
                self.tracks = artistTopTracksAwait.map(\.toPlayable)
            case (.track, .apple):
                guard let song: Song = try? await MusicSearchService().lookup(id: playableContent.content.id), let artistID = song.artists?.first?.id.description else { return }
                guard let artist: Artist = try? await MusicSearchService().lookup(id: artistID) else { return }
                guard let topTracks = artist.topSongs, let albums = artist.albums else { return }
                self.tracks = topTracks.map(\.toPlayable)
                self.albums = albums.map(\.toPlayable)
                artworkURL = artist.artwork?.url(width: 500, height: 500)
                playableContent = artist.toPlayable
            case (.libraryTrack, .apple):
                guard let catalogSong = await MusicSearchService().appleLibraryLookup(id: playableContent.content.id), let id = catalogSong.data.first?.id else { return }
                guard let song: Song = try? await MusicSearchService().lookup(id: id), let artistID = song.artists?.first?.id.description else { return }
                guard let artist: Artist = try? await MusicSearchService().lookup(id: artistID) else { return }
                guard let topTracks = artist.topSongs, let albums = artist.albums else { return }
                self.tracks = topTracks.map(\.toPlayable)
                self.albums = albums.map(\.toPlayable)
                artworkURL = artist.artwork?.url(width: 500, height: 500)
                playableContent = artist.toPlayable
            case (.track, .spotify):
                guard let song = await MusicSearchService().spotifyTrackLookup(id: playableContent.content.id), let artistID = song.artists.first?.id else { return }
                async let artist = MusicSearchService().spotifyArtist(id: artistID)
                async let artistAlbums = MusicSearchService().spotifyArtistAlbums(id: artistID)
                async let artistTopTracks = MusicSearchService().spotifyArtistTopTracks(id: artistID)

                guard let artistAwait = await artist else { return }
                guard let artistAlbumsAwait = await artistAlbums else { return }
                let artistTopTracksAwait = await artistTopTracks

                playableContent = artistAwait.toPlayable
                albums = artistAlbumsAwait.items.map(\.toPlayable)
                artworkURL = artistAwait.images.biggestImageURL
                self.tracks = artistTopTracksAwait.map(\.toPlayable)
            case (.album, .apple):
                guard let album: Album = try? await MusicSearchService().lookup(id: playableContent.content.id), let artistID = album.artists?.first?.id.description else { return }
                guard let artist: Artist = try? await MusicSearchService().lookup(id: artistID) else { return }
                guard let topTracks = artist.topSongs, let albums = artist.albums else { return }
                self.tracks = topTracks.map(\.toPlayable)
                self.albums = albums.map(\.toPlayable)
                artworkURL = artist.artwork?.url(width: 500, height: 500)
                playableContent = artist.toPlayable
            case (.album, .spotify):
                guard let song = await MusicSearchService().spotifyAlbumLookup(id: playableContent.content.id),
                      let artistID = song.artists.first?.id else { return }
                async let artist = MusicSearchService().spotifyArtist(id: artistID)
                async let artistAlbums = MusicSearchService().spotifyArtistAlbums(id: artistID)
                async let artistTopTracks = MusicSearchService().spotifyArtistTopTracks(id: artistID)

                guard let artistAwait = await artist else { return }
                guard let artistAlbumsAwait = await artistAlbums else { return }
                let artistTopTracksAwait = await artistTopTracks

                playableContent = artistAwait.toPlayable
                albums = artistAlbumsAwait.items.map(\.toPlayable)
                artworkURL = artistAwait.images.biggestImageURL
                self.tracks = artistTopTracksAwait.map(\.toPlayable)
            case (.track, .library):
                artworkURL = nil
                guard let artistName = playableContent.metadata?.artist?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }

                playableContent = PlayableContent(
                    title: artistName,
                    subtitle: playableContent.subtitle,
                    artwork: nil,
                    content: playableContent.content
                )

                self.albums = await sonosService.libraryArtist(name: artistName)
                self.tracks = await sonosService.libraryArtist(name: artistName + "/").suffix(10)
            case (.album, .library):
                artworkURL = nil

                guard let artistName = playableContent.metadata?.artist?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }

                playableContent = PlayableContent(
                    title: artistName,
                    subtitle: playableContent.subtitle,
                    artwork: nil,
                    content: playableContent.content
                )
                self.albums = await sonosService.libraryArtist(name: artistName)
                self.tracks = await sonosService.libraryArtist(name: artistName + "/").suffix(10)
            case (.artist, .library):
                artworkURL = nil

                artworkURL = playableContent.artwork
                self.albums = await sonosService.libraryLookup(ID: playableContent.id)
                self.tracks = await sonosService.libraryLookup(ID: playableContent.id + "/").suffix(10)
            // MARK: - Tidal
            case (.track, .tidal):
                artworkURL = nil
                artworkURL = playableContent.artwork

                if let artistID = playableContent.metadata?.artistID {
                    let artistAlbums = await MusicSearchService().lookupTidalArtistAlbums(id: artistID)
                    let artistTopTracks = await MusicSearchService().lookupTidalArtistTracks(id: artistID)
                    let artist = await MusicSearchService().lookupTidalArtist(id: artistID)

                    albums = artistAlbums
                    self.tracks = artistTopTracks
                    if let artist {
                        self.playableContent = artist
                    }
                } else {
                    guard let artistID = await MusicSearchService().lookupTidalTrack(with: playableContent.id)?.metadata?.artistID else { return }
                    let artistAlbums = await MusicSearchService().lookupTidalArtistAlbums(id: artistID)
                    let artistTopTracks = await MusicSearchService().lookupTidalArtistTracks(id: artistID)
                    let artist = await MusicSearchService().lookupTidalArtist(id: artistID)

                    albums = artistAlbums
                    self.tracks = artistTopTracks
                    if let artist {
                        self.playableContent = artist
                    }
                }
                // MARK: Rate Limited
//                if let artistID = playableContent.metadata?.artistID {
//                    async let artistAlbums = MusicSearchService().lookupTidalArtistAlbums(id: artistID)
//                    async let artistTopTracks = MusicSearchService().lookupTidalArtistTracks(id: artistID)
//                    async let artist = MusicSearchService().lookupTidalArtist(id: artistID)
//
//                    let artistAlbumsAwait = await artistAlbums
//                    let artistTopTracksAwait = await artistTopTracks
//
//                    albums = artistAlbumsAwait
//                    self.tracks = artistTopTracksAwait
//                    if let artistAwait = await artist {
//                        self.playableContent = artistAwait
//                    }
//                } else {
//                    guard let artistID = await MusicSearchService().lookupTidalTrack(with: playableContent.id)?.metadata?.artistID else { return }
//                    async let artistAlbums = MusicSearchService().lookupTidalArtistAlbums(id: artistID)
//                    async let artistTopTracks = MusicSearchService().lookupTidalArtistTracks(id: artistID)
//                    async let artist = MusicSearchService().lookupTidalArtist(id: artistID)
//
//                    let artistAlbumsAwait = await artistAlbums
//                    let artistTopTracksAwait = await artistTopTracks
//
//                    albums = artistAlbumsAwait
//                    self.tracks = artistTopTracksAwait
//                    if let artistAwait = await artist {
//                        self.playableContent = artistAwait
//                    }
//                }
            case (.album, .tidal):
                artworkURL = nil
                artworkURL = playableContent.artwork

                if let artistID = playableContent.metadata?.artistID {
                    let artistAlbums = await MusicSearchService().lookupTidalArtistAlbums(id: artistID)
                    let artistTopTracks = await MusicSearchService().lookupTidalArtistTracks(id: artistID)
                    let artist = await MusicSearchService().lookupTidalArtist(id: artistID)

                    albums = artistAlbums
                    self.tracks = artistTopTracks
                    if let artist {
                        self.playableContent = artist
                    }
                } else {
                    guard let artistID = await MusicSearchService().lookupTidalTrack(with: playableContent.id)?.metadata?.artistID else { return }
                    let artistAlbums = await MusicSearchService().lookupTidalArtistAlbums(id: artistID)
                    let artistTopTracks = await MusicSearchService().lookupTidalArtistTracks(id: artistID)
                    let artist = await MusicSearchService().lookupTidalArtist(id: artistID)

                    albums = artistAlbums
                    self.tracks = artistTopTracks
                    if let artist {
                        self.playableContent = artist
                    }
                }
                // MARK: Rate Limited
//                if let artistID = playableContent.metadata?.artistID {
//                    async let artistAlbums = MusicSearchService().lookupTidalArtistAlbums(id: artistID)
//                    async let artistTopTracks = MusicSearchService().lookupTidalArtistTracks(id: artistID)
//                    async let artist = MusicSearchService().lookupTidalArtist(id: artistID)
//
//                    let artistAlbumsAwait = await artistAlbums
//                    let artistTopTracksAwait = await artistTopTracks
//
//                    albums = artistAlbumsAwait
//                    self.tracks = artistTopTracksAwait
//                    if let artistAwait = await artist {
//                        self.playableContent = artistAwait
//                    }
//                } else {
//                    guard let artistID = await MusicSearchService().lookupTidalTrack(with: playableContent.id)?.metadata?.artistID else { return }
//                    async let artistAlbums = MusicSearchService().lookupTidalArtistAlbums(id: artistID)
//                    async let artistTopTracks = MusicSearchService().lookupTidalArtistTracks(id: artistID)
//                    async let artist = MusicSearchService().lookupTidalArtist(id: artistID)
//
//                    let artistAlbumsAwait = await artistAlbums
//                    let artistTopTracksAwait = await artistTopTracks
//
//                    albums = artistAlbumsAwait
//                    self.tracks = artistTopTracksAwait
//                    if let artistAwait = await artist {
//                        self.playableContent = artistAwait
//                    }
//                }
            case (.artist, .tidal):
                artworkURL = nil
                artworkURL = playableContent.artwork
                async let artistAlbums = MusicSearchService().lookupTidalArtistAlbums(id: playableContent.content.id)
                async let artistTopTracks = MusicSearchService().lookupTidalArtistTracks(id: playableContent.content.id)

                let artistAlbumsAwait = await artistAlbums
                let artistTopTracksAwait = await artistTopTracks

                albums = artistAlbumsAwait
                self.tracks = artistTopTracksAwait

            // MARK: Plex
            case (.track, .plex):
                if let artistID = playableContent.metadata?.artistID {
                    let albums = await MusicSearchService().lookupPlexArtistAlbums(id: artistID)
                    let artist = await MusicSearchService().lookupPlexArtist(id: artistID)
                    self.albums = albums
                    if let artist {
                        self.playableContent = artist
                        artworkURL = playableContent.artwork
                    }
                } else {
                    guard let id = playableContent.id.removingPercentEncoding?.components(separatedBy: ":").last,
                          let artistID = await MusicSearchService().lookupPlexSong(with: id)?.metadata?.artistID else { return }
                    let albums = await MusicSearchService().lookupPlexArtistAlbums(id: artistID)
                    let artist = await MusicSearchService().lookupPlexArtist(id: artistID)

                    self.albums = albums
                    if let artist {
                        self.playableContent = artist
                        artworkURL = playableContent.artwork
                    }
                }
            case (.album, .plex):
                artworkURL = nil
                artworkURL = playableContent.artwork
                guard let artistID = playableContent.metadata?.artistID else { return }
                let albums = await MusicSearchService().lookupPlexArtistAlbums(id: artistID)
                self.albums = albums
                if let artistID = playableContent.metadata?.artistID {
                    let artist = await MusicSearchService().lookupPlexArtist(id: artistID)
                    if let artist {
                        self.playableContent = artist
                        artworkURL = playableContent.artwork
                    }
                }
            case (.artist, .plex):
                let albums = await MusicSearchService().lookupPlexArtistAlbums(id: playableContent.content.id)
                self.albums = albums
            default:
                break
            }
            isLoading = false
        }
    }
}

#Preview {
    // https://music.apple.com/us/playlist/dua-lipa-essentials/pl.ee7b1aea4b5f42d398e6cd3084f7396b
    // https://music.apple.com/us/album/future-nostalgia-the-moonlight-edition/1551178998
    /// 6M2wZ9GZgrQXHCFfjv46we

    NavigationStack {
        ArtistDetailView(playableContent: PlayableContent(
            title: "Dua Lipa",
            subtitle: "",
            artwork: nil,
            content: MediaContent(
                service: .spotify,
                id: "6M2wZ9GZgrQXHCFfjv46we",
                type: .artist,
                location: nil
            ))
        )
        .environment(SonosService.shared)
        .environment(Router())
    }
}
