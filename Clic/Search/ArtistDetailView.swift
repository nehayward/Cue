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
    @Environment(AlertService.self) private var alertService

    @State var playableContent: PlayableContent
    @State private var tracks: [PlayableContent] = []
    @State private var albums: [PlayableContent] = []
    @State private var liveAlbums: [PlayableContent] = []
    @State private var singles: [PlayableContent] = []
    @State private var allAlbums: [PlayableContent] = []
    @State private var latestRelease: PlayableContent?
    
    @State private var artworkURL: URL?
    @State private var isLoading: Bool = false
    @State private var albumType: Int = 0
    
    @AppStorage("isTopSongsExpanded") private var isTopSongsExpanded: Bool = true
    
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
                                router?.presentedSheet = .selectGroup(selectedGroupService: selectedGroupService, content: playableContent)
                                return
                            }
                            HapticManager.shared.fireHaptic(.buttonPress)
                            do {
                                let radioContent = playableContent.toRadio
                                alertService.showAlertContent(with: radioContent, subtitle: "Radio")
                                try await sonosService.startRadio(content: radioContent, group: group)
                                playHistoryService.history.remove(radioContent)
                                playHistoryService.history.insert(radioContent, at: 0)
                            } catch {
                                alertService.showAlert(with: "Please authorize \(playableContent.content.service.title) in Sonos", imageName: "exclamationmark.triangle.fill")
                            }
                        }
                    } label: {
                        Text("Start Radio \(Image(systemName: "radio.fill"))")
                            .padding(.horizontal)
                            .padding(.vertical, 12)
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
            
            if let latestRelease {
                Section {
                    PlayableContentView(item: latestRelease, hideContentType: true)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } header: {
                    HStack {
                        Text("Latest")
#if targetEnvironment(macCatalyst)
                            .foregroundStyle(.foreground)
                            .font(.title2)
#endif
                        Spacer()
                    }
                }
            }

            if !tracks.isEmpty {
                Section(isExpanded: $isTopSongsExpanded) {
                    ForEach(tracks) { track in
                        PlayableContentView(item: track, hideContentType: true)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    HStack {
                        Text("Popular")
                        #if targetEnvironment(macCatalyst)
                            .foregroundStyle(.foreground)
                            .font(.title2)
                        #endif
                        Spacer()
                        Button {
                            Task { @MainActor in
                                let queueAllSongs: ((GroupRoom) async throws -> Void) = { group in
                                    HapticManager.shared.fireHaptic(.buttonPress)
                                    do {
                                        alertService.showAlert(with: "Playing Top Songs", imageName: "star.fill")
                                        try await sonosService.queue(contents: tracks, group: group, position: .next)
                                        await sonosService.play(ip: group.coordinatorRoom.ip)
                                    }
                                }
                                guard let group = selectedGroupService.group else {
                                    router?.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onSelection: queueAllSongs))
                                    return
                                }
                                try await queueAllSongs(group)
                            }
                        } label: {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.accent)
                        }
                        .bold()
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .tint(.accent)
                        .help(Text("Play All Top Songs"))
//                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 20))
                    }
                }
            }

            Section {
                switch albumType {
                case 1:
                    ForEach(liveAlbums) { album in
                        VStack {
                            PlayableContentView(item: album, hideContentType: true)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                case 2:
                    ForEach(singles) { album in
                        VStack {
                            PlayableContentView(item: album, hideContentType: true)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                case 3:
                    ForEach(allAlbums) { album in
                        VStack {
                            PlayableContentView(item: album, hideContentType: true)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                default:
                    ForEach(albums) { album in
                        VStack {
                            PlayableContentView(item: album, hideContentType: true)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                if !albums.isEmpty {
                    HStack {
                        Button {
                            Task { @MainActor in
                                let queueAll: ((GroupRoom) async throws -> Void) = { group in
                                    HapticManager.shared.fireHaptic(.buttonPress)
                                    do {
                                        var albums: [PlayableContent] = albums
                                        switch albumType {
                                        case 1:
                                            albums = liveAlbums
                                        case 2:
                                            albums = singles
                                        case 3:
                                            albums = allAlbums
                                        default:
                                            break
                                        }
                                        alertService.showAlert(with: "Playing \(albums.count) albums", imageName: "figure.dance")
                                        try await sonosService.queue(contents: albums.reversed(), group: group, position: .replace)
                                        await sonosService.play(ip: group.coordinatorRoom.ip)
                                    }
                                }
                                guard let group = selectedGroupService.group else {
                                    router?.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onSelection: queueAll))
                                    return
                                }
                                try await queueAll(group)
                            }
                        } label: {
                            Text("Play Discography")
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
            } header: {
                if [.apple, .plex].contains(playableContent.content.service), !albums.isEmpty {
                    Picker("Album", selection: $albumType) {
                        Text("Album")
                            .tag(0)
                        Text("Live")
                            .tag(1)
                        Text("Singles")
                            .tag(2)
                        Text("All")
                            .tag(3)
                    }
                    .pickerStyle(.segmented)
                } else if !albums.isEmpty {
                    HStack {
                            Text("Albums")
    #if targetEnvironment(macCatalyst)
                                .foregroundStyle(.foreground)
                                .font(.title2)
    #endif
                    }
                }
                
            }
        }
        .miniPlayerOnScrollHandler()
        .listStyle(.sidebar)
        .listSectionSeparator(.hidden)
        .navigationTitle(playableContent.title)
        .headerProminence(.increased)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .contentMargins(.top, EdgeInsets(), for: .scrollContent)
        .task {
            isLoading = true
            artworkURL = playableContent.artwork
            switch (playableContent.content.type, playableContent.content.service) {
            case (.artist, .apple):
                guard let artist: Artist = try? await MusicSearchService.shared.lookup(id: playableContent.content.id) else { return }
                guard let topTracks = artist.topSongs, let albums = artist.albums else { return }
                self.tracks = topTracks.map(\.toPlayable)
                self.albums = albums.map(\.toPlayable)
                    .filter { !($0.metadata?.isSingle ?? false) }
                    .sorted { (album1, album2) in
                        let year1 = album1.metadata?.albumYear ?? .now
                        let year2 = album2.metadata?.albumYear ?? .now
                        return year1 > year2
                    }
                artworkURL = artist.artwork?.url(width: 500, height: 500)
                
                guard let allArtist: Artist = try? await MusicSearchService.shared.artistCatalog(id: playableContent.content.id) else { return }
                latestRelease = allArtist.latestRelease?.toPlayable
                
                if let liveAlbums = allArtist.liveAlbums {
                    self.liveAlbums = liveAlbums.map(\.toPlayable)
                        .sorted { (album1, album2) in
                            let year1 = album1.metadata?.albumYear ?? .now
                            let year2 = album2.metadata?.albumYear ?? .now
                            return year1 > year2
                        }
                }
                
                artworkURL = artist.artwork?.url(width: 500, height: 500)
                playableContent = artist.toPlayable
                
                if let all: [PlayableContent] = try? await MusicSearchService.shared.allAlbums(id: playableContent.content.id) {
                    self.allAlbums = all
                }
            case (.libraryArtist, .apple):
                if let url = await MusicSearchService.shared.appleLibraryArtistArtwork(name: playableContent.title) {
                    artworkURL = url
                }
                if let albums = await MusicSearchService.shared.appleLibraryArtistAlbumLookup(id: playableContent.content.id) {
                    self.albums = albums.data.compactMap(\.toPlayable)
                }
            case (.artist, .spotify):
                async let artist = MusicSearchService.shared.spotifyArtist(id: playableContent.content.id)
                async let artistAlbums = MusicSearchService.shared.spotifyArtistAlbums(id: playableContent.content.id)
                async let artistTopTracks = MusicSearchService.shared.spotifyArtistTopTracks(id: playableContent.content.id)

                guard let artistAwait = await artist else { return }
                guard let artistAlbumsAwait = await artistAlbums else { return }
                let artistTopTracksAwait = await artistTopTracks

                playableContent = artistAwait.toPlayable
                albums = artistAlbumsAwait.items.map(\.toPlayable)
                self.tracks = artistTopTracksAwait.compactMap(\.toPlayable)
            case (.track, .apple):
                guard let song: Song = try? await MusicSearchService.shared.lookup(id: playableContent.content.id), let artistID = song.artists?.first?.id.description else { return }
                guard let artist: Artist = try? await MusicSearchService.shared.lookup(id: artistID) else { return }
                guard let allArtist: Artist = try? await MusicSearchService.shared.artistCatalog(id: artistID) else { return }
                latestRelease = allArtist.latestRelease?.toPlayable
                
                guard let topTracks = artist.topSongs, let albums = artist.albums else { return }
                self.tracks = topTracks.map(\.toPlayable)
                self.albums = albums.map(\.toPlayable)
                    .filter { !($0.metadata?.isSingle ?? false) }
                    .sorted { (album1, album2) in
                        let year1 = album1.metadata?.albumYear ?? .now
                        let year2 = album2.metadata?.albumYear ?? .now
                        return year1 > year2
                    }
                
                if let liveAlbums = allArtist.liveAlbums {
                    self.liveAlbums = liveAlbums.map(\.toPlayable)
                        .sorted { (album1, album2) in
                            let year1 = album1.metadata?.albumYear ?? .now
                            let year2 = album2.metadata?.albumYear ?? .now
                            return year1 > year2
                        }
                }
                
                artworkURL = artist.artwork?.url(width: 500, height: 500)
                playableContent = artist.toPlayable
                
                if let all: [PlayableContent] = try? await MusicSearchService.shared.allAlbums(id: artistID) {
                    self.allAlbums = all
                }
            case (.libraryTrack, .apple):
                guard let catalogSong = await MusicSearchService.shared.appleLibraryLookup(id: playableContent.content.id), let id = catalogSong.data.first?.id else { return }
                guard let song: Song = try? await MusicSearchService.shared.lookup(id: id), let artistID = song.artists?.first?.id.description else { return }
                guard let artist: Artist = try? await MusicSearchService.shared.lookup(id: artistID) else { return }
                guard let topTracks = artist.topSongs, let albums = artist.albums else { return }
                self.tracks = topTracks.map(\.toPlayable)
                self.albums = albums.map(\.toPlayable)
                artworkURL = artist.artwork?.url(width: 500, height: 500)
                playableContent = artist.toPlayable
            case (.track, .spotify):
                guard let song = await MusicSearchService.shared.spotifyTrackLookup(id: playableContent.content.id), let artistID = song.artists.first?.id else { return }
                async let artist = MusicSearchService.shared.spotifyArtist(id: artistID)
                async let artistAlbums = MusicSearchService.shared.spotifyArtistAlbums(id: artistID)
                async let artistTopTracks = MusicSearchService.shared.spotifyArtistTopTracks(id: artistID)

                guard let artistAwait = await artist else { return }
                guard let artistAlbumsAwait = await artistAlbums else { return }
                let artistTopTracksAwait = await artistTopTracks

                playableContent = artistAwait.toPlayable
                albums = artistAlbumsAwait.items.map(\.toPlayable)
                artworkURL = artistAwait.images.biggestImageURL
                self.tracks = artistTopTracksAwait.compactMap(\.toPlayable)
                
//                guard let song = await MusicSearchService.shared.spotifyTrackLookup(id: playableContent.content.id) else { return }
//                async let artistAlbums = MusicSearchService.shared.spotifyArtistAlbums(id: song.artistIdOnly)
//                async let artistTopTracks = MusicSearchService.shared.spotifyArtistTopTracks(id: song.artistIdOnly)
//                
//                guard let artistAlbumsAwait = await artistAlbums else { return }
//                guard let artistTopTracksAwait = await artistTopTracks else { return }
//                
//                print(artistAlbumsAwait)
//                playableContent = song.toAlbumPlayable
//                albums = artistAlbumsAwait.artists.compactMap(\.toPlayable)
//                if let radioURL = artistTopTracksAwait.songs.first?.albumArtURI, let url = URL(string: radioURL) {
//                    artworkURL = url
//                }
//                self.tracks = artistTopTracksAwait.songs.compactMap(\.toPlayable)
            case (.album, .apple):
                guard let album: Album = try? await MusicSearchService.shared.lookup(id: playableContent.content.id), let artistID = album.artists?.first?.id.description else { return }
                guard let artist: Artist = try? await MusicSearchService.shared.artistCatalog(id: artistID) else { return }
                latestRelease = artist.latestRelease?.toPlayable
                
                guard let topTracks = artist.topSongs, let albums = artist.albums else { return }
                self.tracks = topTracks.map(\.toPlayable)
                self.albums = albums.map(\.toPlayable)
                    .filter { !($0.metadata?.isSingle ?? false) }
                    .sorted { (album1, album2) in
                    let year1 = album1.metadata?.albumYear ?? .now
                    let year2 = album2.metadata?.albumYear ?? .now
                    return year1 > year2
                }
                
                if let liveAlbums = artist.liveAlbums {
                    self.liveAlbums = liveAlbums.map(\.toPlayable)
                        .sorted { (album1, album2) in
                            let year1 = album1.metadata?.albumYear ?? .now
                            let year2 = album2.metadata?.albumYear ?? .now
                            return year1 > year2
                        }
                }
                
                artworkURL = artist.artwork?.url(width: 500, height: 500)
                playableContent = artist.toPlayable
                
                if let all: [PlayableContent] = try? await MusicSearchService.shared.allAlbums(id: artistID) {
                    self.allAlbums = all
                }
            case (.album, .spotify):
                guard let song = await MusicSearchService.shared.spotifyAlbumLookup(id: playableContent.content.id),
                      let artistID = song.artists?.first?.id else { return }
                async let artist = MusicSearchService.shared.spotifyArtist(id: artistID)
                async let artistAlbums = MusicSearchService.shared.spotifyArtistAlbums(id: artistID)
                async let artistTopTracks = MusicSearchService.shared.spotifyArtistTopTracks(id: artistID)

                guard let artistAwait = await artist else { return }
                guard let artistAlbumsAwait = await artistAlbums else { return }
                let artistTopTracksAwait = await artistTopTracks

                playableContent = artistAwait.toPlayable
                albums = artistAlbumsAwait.items.map(\.toPlayable)
                artworkURL = artistAwait.images.biggestImageURL
                self.tracks = artistTopTracksAwait.compactMap(\.toPlayable)
            case (.track, .library):
                artworkURL = nil
                guard let artistName = playableContent.metadata?.artist?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }

                playableContent = PlayableContent(
                    title: artistName,
                    subtitle: playableContent.subtitle,
                    thumbnail: nil,
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
                    thumbnail: nil,
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
                    let artistAlbums = await MusicSearchService.shared.lookupTidalArtistAlbums(id: artistID)
                    try? await Task.sleep(for: .milliseconds(200))
                    let artistTopTracks = await MusicSearchService.shared.lookupTidalArtistTracks(id: artistID)
                    try? await Task.sleep(for: .milliseconds(200))
                    let artist = await MusicSearchService.shared.lookupTidalArtist(id: artistID)

                    albums = artistAlbums
                    self.tracks = artistTopTracks
                    if let artist {
                        self.playableContent = artist
                        artworkURL = playableContent.artwork
                    }
                } else {
                    guard let artistID = await MusicSearchService.shared.lookupTidalTrack(with: playableContent.id)?.metadata?.artistID else { return }
                    try? await Task.sleep(for: .milliseconds(200))
                    let artistAlbums = await MusicSearchService.shared.lookupTidalArtistAlbums(id: artistID)
                    try? await Task.sleep(for: .milliseconds(200))
                    let artistTopTracks = await MusicSearchService.shared.lookupTidalArtistTracks(id: artistID)
                    try? await Task.sleep(for: .milliseconds(200))
                    let artist = await MusicSearchService.shared.lookupTidalArtist(id: artistID)

                    albums = artistAlbums
                    self.tracks = artistTopTracks
                    if let artist {
                        self.playableContent = artist
                        artworkURL = playableContent.artwork
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
                    let artistAlbums = await MusicSearchService.shared.lookupTidalArtistAlbums(id: artistID)
                    try? await Task.sleep(for: .milliseconds(300))
                    let artistTopTracks = await MusicSearchService.shared.lookupTidalArtistTracks(id: artistID)
                    try? await Task.sleep(for: .milliseconds(300))
                    let artist = await MusicSearchService.shared.lookupTidalArtist(id: artistID)

                    albums = artistAlbums
                    self.tracks = artistTopTracks
                    if let artist {
                        self.playableContent = artist
                    }
                } else {
                    guard let artistID = await MusicSearchService.shared.lookupTidalTrack(with: playableContent.id)?.metadata?.artistID else { return }
                    try? await Task.sleep(for: .milliseconds(200))

                    let artistAlbums = await MusicSearchService.shared.lookupTidalArtistAlbums(id: artistID)
                    try? await Task.sleep(for: .milliseconds(200))

                    let artistTopTracks = await MusicSearchService.shared.lookupTidalArtistTracks(id: artistID)
                    try? await Task.sleep(for: .milliseconds(200))
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
                async let artistAlbums = MusicSearchService.shared.lookupTidalArtistAlbums(id: playableContent.content.id)
                try? await Task.sleep(for: .milliseconds(200))
                async let artistTopTracks = MusicSearchService.shared.lookupTidalArtistTracks(id: playableContent.content.id)

                let artistAlbumsAwait = await artistAlbums
                let artistTopTracksAwait = await artistTopTracks

                albums = artistAlbumsAwait
                self.tracks = artistTopTracksAwait

            // MARK: Plex
            case (.track, .plex):
                if let artistID = playableContent.metadata?.artistID {
                    async let albums = MusicSearchService.shared.lookupPlexArtistAlbums(id: artistID)
                    async let (live, singles, others) = MusicSearchService.shared.getPlexArtistAllAlbums(id: artistID)
                    async let artist = MusicSearchService.shared.lookupPlexArtist(id: artistID)
                    
                    let (albumsResult, (liveResult, singlesResult, othersResult), artistResult) = await (albums, (live, singles, others), artist)
                    
                    self.allAlbums = albumsResult + liveResult + singlesResult + othersResult
                    self.liveAlbums = liveResult
                    self.singles = singlesResult
                    
                    if let artistResult {
                        self.playableContent = artistResult
                        artworkURL = playableContent.artwork
                    }
                } else {
                    guard let id = playableContent.id.removingPercentEncoding?.components(separatedBy: ":").last,
                          let artistID = await MusicSearchService.shared.lookupPlexSong(with: id)?.metadata?.artistID else { return }
                    
                    async let albums = MusicSearchService.shared.lookupPlexArtistAlbums(id: artistID)
                    async let (live, singles, others) = MusicSearchService.shared.getPlexArtistAllAlbums(id: artistID)
                    async let artist = MusicSearchService.shared.lookupPlexArtist(id: artistID)
                    
                    let (albumsResult, (liveResult, singlesResult, othersResult), artistResult) = await (albums, (live, singles, others), artist)
                    
                    self.albums = albumsResult
                    self.allAlbums = albumsResult + liveResult + singlesResult + othersResult
                    self.liveAlbums = liveResult
                    self.singles = singlesResult
                    
                    if let artistResult {
                        self.playableContent = artistResult
                        artworkURL = playableContent.artwork
                    }
                }
            case (.album, .plex):
                artworkURL = nil
                artworkURL = playableContent.artwork
                guard let artistID = playableContent.metadata?.artistID else { return }
                
                async let albums = MusicSearchService.shared.lookupPlexArtistAlbums(id: artistID)
                async let (live, singles, others) = MusicSearchService.shared.getPlexArtistAllAlbums(id: artistID)
                async let artist = MusicSearchService.shared.lookupPlexArtist(id: artistID)
                
                let (albumsResult, (liveResult, singlesResult, othersResult), artistResult) = await (albums, (live, singles, others), artist)
                
                self.albums = albumsResult
                self.allAlbums = albumsResult + liveResult + singlesResult + othersResult
                self.liveAlbums = liveResult
                self.singles = singlesResult
                
                if let artistResult {
                    self.playableContent = artistResult
                    artworkURL = playableContent.artwork
                }
            case (.artist, .plex):
                async let albums = MusicSearchService.shared.lookupPlexArtistAlbums(id: playableContent.content.id)
                async let (live, singles, others) = MusicSearchService.shared.getPlexArtistAllAlbums(id: playableContent.content.id)
                
                let (albumsResult, (liveResult, singlesResult, othersResult)) = await (albums, (live, singles, others))
                
                self.albums = albumsResult
                self.allAlbums = albumsResult + liveResult + singlesResult + othersResult
                self.liveAlbums = liveResult
                self.singles = singlesResult
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
            thumbnail: nil,
            artwork: nil,
            content: MediaContent(
                service: .spotify,
                id: "6M2wZ9GZgrQXHCFfjv46we",
                type: .artist,
                location: nil
            ))
        )
        .withEnvironments()
        .environment(SelectedGroupService())
    }
}
