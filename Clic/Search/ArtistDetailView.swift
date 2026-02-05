import CloudStorage
import Defaults
import Glur
import MusicKit
import MusicSearchKit
import NukeUI
import OrderedCollections
import SonosKit
import SwiftUI
import VibesDS

struct ArtistDetailView: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router: Router?
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService
    @Environment(AlertService.self) private var alertService
    
    let playableContent: PlayableContent
    @State private var tracks: [PlayableContent] = []
    @State private var albums: [PlayableContent] = []
    @State private var liveAlbums: [PlayableContent] = []
    @State private var singles: [PlayableContent] = []
    @State private var allAlbums: [PlayableContent] = []
    @State private var latestRelease: PlayableContent?
    
    @State private var artworkURL: URL?
    @State private var isLoading: Bool = false
    @State private var albumType: AlbumCategory = .albums
    @State private var artworkLoaded: Bool = false
    @State private var artistContent: PlayableContent?
    @State private var showTitle: Bool = false
    
    @AppStorage("isTopSongsExpanded") private var isTopSongsExpanded: Bool = true
    @AppStorage("isAlbumsExpanded") private var isAlbumsExpanded: Bool = true
    
    var maxHeight: Double {
        UIDevice.current.userInterfaceIdiom == .phone ? 340 : 400
    }
    
    // MARK: - Computed Properties
    
    private enum AlbumCategory: Int, CaseIterable {
        case albums = 0
        case live = 1
        case singles = 2
        case all = 3
        
        var title: String {
            switch self {
            case .albums: "Album"
            case .live: "Live"
            case .singles: "Singles"
            case .all: "All"
            }
        }
        
        
        static func firstAvailable(
            albums: [PlayableContent],
            live: [PlayableContent],
            singles: [PlayableContent],
            all: [PlayableContent]
        ) -> AlbumCategory {
            let availability: [(AlbumCategory, Bool)] = [
                (.albums, !albums.isEmpty),
                (.live, !live.isEmpty),
                (.singles, !singles.isEmpty),
                (.all, !all.isEmpty)
            ]
            
            return availability.first(where: { $0.1 })?.0 ?? .all
        }
    }
    
    private var currentAlbums: [PlayableContent] {
        switch albumType {
        case .albums: albums
        case .live: liveAlbums
        case .singles: singles
        case .all: allAlbums
        }
    }
    
    private var supportsRadio: Bool {
        guard let artistContent else { return false }
        return [.spotify, .apple].contains(artistContent.content.service)
            && artistContent.content.type != .libraryArtist
    }

    private var supportsAlbumCategories: Bool {
        guard let artistContent else { return false }
        return [.apple, .plex].contains(artistContent.content.service)
    }
    
    // MARK: - Body
    
    var body: some View {
        List {
            artworkSection
            latestReleaseSection
            popularTracksSection
            albumsSection
        }
        .animation(.smooth(duration: 0.3), value: isTopSongsExpanded)
        .animation(.smooth(duration: 0.3), value: isAlbumsExpanded)
        .ignoresSafeArea(edges: .top)
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .navigationTitle(artistContent?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onScrollOffset(exceeds: 380, set: $showTitle)
//        #if targetEnvironment(macCatalyst)
        .scrollEdgeEffectHidden26(!showTitle)
//        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(artistContent?.title ?? "")
                    .opacity(showTitle ? 1 : 0)
            }
        }
        .animation(.spring, value: showTitle)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .contentMargins(.top, EdgeInsets(), for: .scrollContent)
        .task { await loadArtistData() }
    }
    
    // MARK: - Artwork Section
    
    @ViewBuilder
    private var artworkSection: some View {
        Color.clear.overlay {
            ZStack {
                LazyImage(url: artworkURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .blur(radius: 100)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: maxHeight)
                LazyImage(url: artworkURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .glur(radius: 30, // The total radius of the blur effect when fully applied.
                                  offset: 0.6, // The distance from the view's edge to where the effect begins, relative to the view's size.
                                  interpolation: 0.4, // The distance from the offset to where the effect is fully applied, relative to the view's size.
                                  direction: .down, // The direction in which the effect is applied.
                                  noise: 0.1, // The amount of noise that should be applied to the view.
                                  drawingGroup: false // Whether or not to pre-render the modified view with `drawingGroup()`.
                            )
                            .frame(maxWidth: 400, maxHeight: maxHeight)
                            .clipped()
                    }
                }
            }
        }
        .overlay {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.7), location: 0.0),
                    .init(color: .clear, location: 0.55)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.95),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .stretchy()
        .overlay {
            if artistContent == nil {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white)
            }
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text(artistContent?.title ?? "")
                    .font(.title)
                    .foregroundStyle(.white)
                    .fontWeight(.black)
                    .fontDesign(.rounded)
                radioButtonOverlay
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .frame(height: maxHeight)
        .listRowBackground(Color.white.opacity(0.001))
        .listSectionSeparator(.hidden)
        .listRowInsets(EdgeInsets())
    }
    
    private var radioButtonOverlay: some View {
        HStack {
            if supportsRadio {
                Button {
                    Task { await startRadio() }
                } label: {
                    Text("Play Radio \(Image(systemName: "radio.fill"))")
                        .padding(4)
                        .foregroundStyle(.white)
                }
                .glassButton()
            }
            if let artistContent, artistContent.content.location != nil {
                OpenInServiceView(item: artistContent)
                    .frame(width: 32, height: 32)
                    .labelStyle(.iconOnly)
                    .glassButton()
            }
        }
    }
    
    // MARK: - Latest Release Section
    
    @ViewBuilder
    private var latestReleaseSection: some View {
        if let latestRelease {
            Section {
                Text("Latest")
                    .font(.headline)
#if targetEnvironment(macCatalyst)
                    .foregroundStyle(.foreground)
                    .font(.title2)
#endif
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowBackground(Color.white.opacity(0.001))
                    .listRowSeparator(.hidden)
                
                PlayableContentView(item: latestRelease, hideContentType: true)
                    .listRowBackground(Color.white.opacity(0.001))
                    .listRowSeparator(.hidden)
            }
        }
    }
    
    // MARK: - Popular Tracks Section
    
    @ViewBuilder
    private var popularTracksSection: some View {
        if !tracks.isEmpty {
            Section {
                CollapsibleHeader(
                    title: "Popular",
                    isExpanded: $isTopSongsExpanded,
                    trailing: { playAllTracksButton }
                )
                
                if isTopSongsExpanded {
                    ForEach(tracks) { track in
                        PlayableContentView(item: track, hideContentType: true)
                            .listRowBackground(Color.white.opacity(0.001))
                            .listRowSeparator(.hidden)
                    }
                }
            }
        }
    }
    
    private var playAllTracksButton: some View {
        Button {
            Task { @MainActor in await playAllTracks() }
        } label: {
            Image(systemName: "play.fill")
                .foregroundStyle(.accent)
        }
        .bold()
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(.accent)
        .help(Text("Play All Top Songs"))
    }
    
    // MARK: - Albums Section
    
    @ViewBuilder
    private var albumsSection: some View {
        if !allAlbums.isEmpty || isLoading || !albums.isEmpty {
            Section {
                CollapsibleHeader(
                    title: supportsAlbumCategories ? nil : "Albums",
                    isExpanded: $isAlbumsExpanded,
                    header: {
                        if supportsAlbumCategories && !allAlbums.isEmpty {
                            albumCategoryPicker
                        }
                    }
                )
                
                if isAlbumsExpanded {
                    ForEach(currentAlbums) { album in
                        PlayableContentView(item: album, hideContentType: true)
                            .listRowBackground(Color.white.opacity(0.001))
                            .listRowSeparator(.hidden)
                    }
                    
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    
                    if !allAlbums.isEmpty {
                        playDiscographyButton
                    }
                }
            }
        }
    }
    
    private var albumCategoryPicker: some View {
        Picker("Album", selection: $albumType) {
            ForEach(AlbumCategory.allCases, id: \.self) { category in
                Text(category.title).tag(category)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var playDiscographyButton: some View {
        HStack {
            Button {
                Task { @MainActor in await playDiscography() }
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
        .listRowBackground(Color.white.opacity(0.001))
        .listRowSeparator(.hidden)
    }
    
    // MARK: - Toolbar
    
//    @ToolbarContentBuilder
//    private var toolbarContent: some ToolbarContent {
//        if playableContent.content.location != nil {
//            ToolbarItemGroup(placement: .topBarTrailing) {
//                Menu {
//                    OpenInServiceView(item: playableContent)
//                } label: {
//                    Image(systemName: "ellipsis")
//                        .frame(maxWidth: 40, maxHeight: .infinity)
//                        .background(.clear)
//                        .bold()
//                        .foregroundStyle(.foreground)
//                        .contentShape(.rect)
//                }
//                .contentShape(.rect)
//            }
//        }
//    }
    
    // MARK: - Actions
    
    private func startRadio() async {
        guard let artistContent else { return }

        guard let group = selectedGroupService.group else {
            router?.presentedSheet = .selectGroup(
                selectedGroupService: selectedGroupService,
                content: artistContent
            )
            return
        }

        HapticManager.shared.fireHaptic(.buttonPress)
        do {
            let radioContent = artistContent.toRadio
            alertService.showAlertContent(with: radioContent, subtitle: "Radio")
            try await sonosService.startRadio(content: radioContent, group: group)
            playHistoryService.history.remove(radioContent)
            playHistoryService.history.insert(radioContent, at: 0)
        } catch {
            alertService.showAlert(
                with: "Please authorize \(artistContent.content.service.title) in Sonos",
                imageName: "exclamationmark.triangle.fill"
            )
        }
    }
    
    private func playAllTracks() async {
        let queueAllSongs: (GroupRoom) async throws -> Void = { group in
            HapticManager.shared.fireHaptic(.buttonPress)
            alertService.showAlert(with: "Playing Top Songs", imageName: "star.fill")
            try await sonosService.queueNext(contents: tracks, group: group)
            await sonosService.play(ip: group.coordinatorRoom.ip)
        }
        
        guard let group = selectedGroupService.group else {
            router?.sheet(to: .selectGroup(
                selectedGroupService: selectedGroupService,
                onSelection: queueAllSongs
            ))
            return
        }
        
        try? await queueAllSongs(group)
    }
    
    private func playDiscography() async {
        let queueAll: (GroupRoom) async throws -> Void = { group in
            HapticManager.shared.fireHaptic(.buttonPress)
            let albumsToPlay = currentAlbums
            alertService.showAlert(
                with: "Playing \(albumsToPlay.count) albums",
                imageName: "figure.dance"
            )
            try await sonosService.queue(
                contents: albumsToPlay.reversed(),
                group: group,
                position: .replace
            )
            await sonosService.play(ip: group.coordinatorRoom.ip)
        }
        
        guard let group = selectedGroupService.group else {
            router?.sheet(to: .selectGroup(
                selectedGroupService: selectedGroupService,
                onSelection: queueAll
            ))
            return
        }
        
        try? await queueAll(group)
    }
    
    // MARK: - Data Loading
    
    private func loadArtistData() async {
        isLoading = true

        // If already an artist type, set immediately (no spinner needed)
        if playableContent.content.type == .artist || playableContent.content.type == .libraryArtist {
            artistContent = playableContent
        }

        switch (playableContent.content.type, playableContent.content.service) {
        case (.artist, .apple):
            await loadAppleArtist()
        case (.libraryArtist, .apple):
            await loadAppleLibraryArtist()
        case (.artist, .spotify):
            await loadSpotifyArtist()
        case (.track, .apple):
            await loadAppleTrackArtist()
        case (.libraryTrack, .apple):
            await loadAppleLibraryTrackArtist()
        case (.track, .spotify):
            await loadSpotifyTrackArtist()
        case (.album, .apple):
            await loadAppleAlbumArtist()
        case (.album, .spotify):
            await loadSpotifyAlbumArtist()
        case (.track, .library), (.album, .library):
            await loadLibraryArtist()
        case (.artist, .library):
            await loadLibraryArtistDirect()
        case (.track, .tidal):
            await loadTidalTrackArtist()
        case (.album, .tidal):
            await loadTidalAlbumArtist()
        case (.artist, .tidal):
            await loadTidalArtist()
        case (.track, .plex):
            await loadPlexTrackArtist()
        case (.album, .plex):
            await loadPlexAlbumArtist()
        case (.artist, .plex):
            await loadPlexArtist()
        default:
            break
        }
        isLoading = false
    }
    
    // MARK: - Apple Music Loading
    
    private func loadAppleArtist() async {
        guard let artist: Artist = try? await MusicSearchService.shared.lookup(
            id: playableContent.content.id
        ) else { return }
        
        guard let topTracks = artist.topSongs, let artistAlbums = artist.albums else { return }
        
        tracks = topTracks.map(\.toPlayable)
        albums = sortAlbumsByYear(artistAlbums.map(\.toPlayable).filter { !($0.metadata?.isSingle ?? false) })
        artworkURL = artist.artwork?.url(width: 500, height: 500)
        
        guard let allArtist: Artist = try? await MusicSearchService.shared.artistCatalog(
            id: playableContent.content.id
        ) else { return }
        
        latestRelease = allArtist.latestRelease?.toPlayable
        
        if let live = allArtist.liveAlbums {
            liveAlbums = sortAlbumsByYear(live.map(\.toPlayable))
        }
        
        artworkURL = artist.artwork?.url(width: 500, height: 500)
        artistContent = artist.toPlayable
        
        if let all: [PlayableContent] = try? await MusicSearchService.shared.allAlbums(
            id: playableContent.content.id
        ) {
            allAlbums = all
        }
    }
    
    private func loadAppleLibraryArtist() async {
        if let url = await MusicSearchService.shared.appleLibraryArtistArtwork(name: playableContent.title, size: 500) {
            artworkURL = url
        }
        
        if let libraryAlbums = await MusicSearchService.shared.appleLibraryArtistAlbumLookup(id: playableContent.content.id) {
            albums = libraryAlbums.data.compactMap(\.toPlayable)
        }
        
        artistContent = playableContent
    }
    
    private func loadAppleTrackArtist() async {
        guard let song: Song = try? await MusicSearchService.shared.lookup(
            id: playableContent.content.id
        ),
              let artistID = song.artists?.first?.id.description
        else { return }
        
        guard let artist: Artist = try? await MusicSearchService.shared.lookup(id: artistID)
        else { return }
        
        guard let allArtist: Artist = try? await MusicSearchService.shared.artistCatalog(id: artistID)
        else { return }
        
        latestRelease = allArtist.latestRelease?.toPlayable
        
        guard let topTracks = artist.topSongs, let artistAlbums = artist.albums else { return }
        
        tracks = topTracks.map(\.toPlayable)
        albums = sortAlbumsByYear(artistAlbums.map(\.toPlayable).filter { !($0.metadata?.isSingle ?? false) })
        
        if let live = allArtist.liveAlbums {
            liveAlbums = sortAlbumsByYear(live.map(\.toPlayable))
        }
        
        artworkURL = artist.artwork?.url(width: 500, height: 500)
        artistContent = artist.toPlayable
        
        if let all: [PlayableContent] = try? await MusicSearchService.shared.allAlbums(id: artistID) {
            allAlbums = all
        }
    }
    
    private func loadAppleLibraryTrackArtist() async {
        guard let catalogSong = await MusicSearchService.shared.appleLibraryLookup(
            id: playableContent.content.id
        ),
              let id = catalogSong.data.first?.id
        else { return }
        
        guard let song: Song = try? await MusicSearchService.shared.lookup(id: id),
              let artistID = song.artists?.first?.id.description
        else { return }
        
        guard let artist: Artist = try? await MusicSearchService.shared.lookup(id: artistID)
        else { return }
        
        guard let topTracks = artist.topSongs, let artistAlbums = artist.albums else { return }
        
        tracks = topTracks.map(\.toPlayable)
        albums = artistAlbums.map(\.toPlayable)
        artworkURL = artist.artwork?.url(width: 500, height: 500)
        artistContent = artist.toPlayable
    }
    
    private func loadAppleAlbumArtist() async {
        guard let album: Album = try? await MusicSearchService.shared.lookup(
            id: playableContent.content.id
        ),
              let artistID = album.artists?.first?.id.description
        else { return }
        
        guard let artist: Artist = try? await MusicSearchService.shared.artistCatalog(id: artistID)
        else { return }
        
        latestRelease = artist.latestRelease?.toPlayable
        
        guard let topTracks = artist.topSongs, let artistAlbums = artist.albums else { return }
        
        tracks = topTracks.map(\.toPlayable)
        albums = sortAlbumsByYear(artistAlbums.map(\.toPlayable).filter { !($0.metadata?.isSingle ?? false) })
        
        if let live = artist.liveAlbums {
            liveAlbums = sortAlbumsByYear(live.map(\.toPlayable))
        }
        
        artworkURL = artist.artwork?.url(width: 500, height: 500)
        artistContent = artist.toPlayable
        
        if let all: [PlayableContent] = try? await MusicSearchService.shared.allAlbums(id: artistID) {
            allAlbums = all
        }
    }
    
    // MARK: - Spotify Loading
    
    private func loadSpotifyArtist() async {
        artworkURL = playableContent.artwork
        artistContent = playableContent
        async let artistAlbums = MusicSearchService.shared.spotifyArtistAlbums(id: playableContent.content.id)
        async let artistTopTracks = MusicSearchService.shared.spotifyArtistTopTracks(id: playableContent.content.id)
        
        guard let albumsResult = await artistAlbums else { return }
        let tracksResult = await artistTopTracks
        
        albums = albumsResult.items.map(\.toPlayable)
        tracks = tracksResult.compactMap(\.toPlayable)
    }
    
    private func loadSpotifyTrackArtist() async {
        guard let song = await MusicSearchService.shared.spotifyTrackLookup(
            id: playableContent.content.id
        ),
              let artistID = song.artists.first?.id
        else { return }
        
        async let artist = MusicSearchService.shared.spotifyArtist(id: artistID)
        async let artistAlbums = MusicSearchService.shared.spotifyArtistAlbums(id: artistID)
        async let artistTopTracks = MusicSearchService.shared.spotifyArtistTopTracks(id: artistID)
        
        guard let artistResult = await artist else { return }
        guard let albumsResult = await artistAlbums else { return }
        let tracksResult = await artistTopTracks
        
        artistContent = artistResult.toPlayable
        albums = albumsResult.items.map(\.toPlayable)
        artworkURL = artistResult.images.biggestImageURL
        tracks = tracksResult.compactMap(\.toPlayable)
        
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
    }
    
    private func loadSpotifyAlbumArtist() async {
        guard let album = await MusicSearchService.shared.spotifyAlbumLookup(id: playableContent.content.id), let artistID = album.artists?.first?.id else { return }
        
        async let artist = MusicSearchService.shared.spotifyArtist(id: artistID)
        async let artistAlbums = MusicSearchService.shared.spotifyArtistAlbums(id: artistID)
        async let artistTopTracks = MusicSearchService.shared.spotifyArtistTopTracks(id: artistID)
        
        guard let artistResult = await artist else { return }
        guard let albumsResult = await artistAlbums else { return }
        let tracksResult = await artistTopTracks
        
        artistContent = artistResult.toPlayable
        albums = albumsResult.items.map(\.toPlayable)
        artworkURL = artistResult.images.biggestImageURL
        tracks = tracksResult.compactMap(\.toPlayable)
    }
    
    // MARK: - Library Loading
    
    private func loadLibraryArtist() async {
        guard let artistName = playableContent.metadata?.artist?.trimmingCharacters(in: .whitespacesAndNewlines).removingPrefix("the ") else { return }
        
        artworkURL = await MusicSearchService.shared.appleLibraryArtistArtwork(name: artistName, size: 500)
        
        artistContent = PlayableContent(
            title: artistName,
            subtitle: playableContent.subtitle,
            thumbnail: nil,
            artwork: nil,
            content: playableContent.content
        )
        
        albums = await sonosService.libraryArtist(name: artistName)
        let allTracks = await sonosService.libraryArtist(name: artistName + "/")
        tracks = Array(allTracks.uniqued(by: \.title).prefix(10))
    }
    
    private func loadLibraryArtistDirect() async {
        artworkURL = await MusicSearchService.shared.appleLibraryArtistArtwork(name: playableContent.title, size: 500)
        albums = await sonosService.libraryLookup(ID: playableContent.id)
        let allTracks = await sonosService.libraryLookup(ID: playableContent.id + "/")
        tracks = Array(allTracks.uniqued(by: \.title).prefix(10))
        artistContent = playableContent
    }
    
    // MARK: - Tidal Loading
    
    private func loadTidalTrackArtist() async {
        artworkURL = playableContent.artwork
        
        if let artistID = playableContent.metadata?.artistID {
            await loadTidalArtistData(id: artistID)
        } else {
            guard let artistID = await MusicSearchService.shared.lookupTidalTrack(
                with: playableContent.id
            )?.metadata?.artistID else { return }
            
            try? await Task.sleep(for: .milliseconds(200))
            await loadTidalArtistData(id: artistID)
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
    }
    
    private func loadTidalAlbumArtist() async {
        artworkURL = playableContent.artwork
        
        if let artistID = playableContent.metadata?.artistID {
            await loadTidalArtistData(id: artistID, delay: 300)
        } else {
            guard let artistID = await MusicSearchService.shared.lookupTidalTrack(
                with: playableContent.id
            )?.metadata?.artistID else { return }
            
            try? await Task.sleep(for: .milliseconds(200))
            await loadTidalArtistData(id: artistID)
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
    }
    
    private func loadTidalArtist() async {
        artworkURL = playableContent.artwork
        
        async let artistAlbums = MusicSearchService.shared.lookupTidalArtistAlbums(
            id: playableContent.content.id
        )
        try? await Task.sleep(for: .milliseconds(200))
        async let artistTopTracks = MusicSearchService.shared.lookupTidalArtistTracks(
            id: playableContent.content.id
        )
        
        albums = await artistAlbums
        tracks = await artistTopTracks
        artistContent = playableContent
    }
    
    private func loadTidalArtistData(id: String, delay: Int = 200) async {
        let artistAlbums = await MusicSearchService.shared.lookupTidalArtistAlbums(id: id)
        try? await Task.sleep(for: .milliseconds(delay))
        
        let artistTopTracks = await MusicSearchService.shared.lookupTidalArtistTracks(id: id)
        try? await Task.sleep(for: .milliseconds(delay))
        
        let artist = await MusicSearchService.shared.lookupTidalArtist(id: id)
        
        albums = artistAlbums
        tracks = artistTopTracks
        
        if let artist {
            artistContent = artist
            artworkURL = playableContent.artwork
        }
    }
    
    // MARK: - Plex Loading
    
    private func loadPlexTrackArtist() async {
        if let artistID = playableContent.metadata?.artistID {
            await loadPlexArtistData(id: artistID, setAlbums: false)
        } else {
            guard let id = playableContent.id.removingPercentEncoding?.components(separatedBy: ":").last,
                  let artistID = await MusicSearchService.shared.lookupPlexSong(with: id)?.metadata?.artistID
            else { return }
            
            await loadPlexArtistData(id: artistID, setAlbums: true)
        }
    }
    
    private func loadPlexAlbumArtist() async {
        artworkURL = playableContent.artwork
        
        guard let artistID = playableContent.metadata?.artistID else { return }
        await loadPlexArtistData(id: artistID, setAlbums: true)
    }
    
    private func loadPlexArtist() async {
        artworkURL = playableContent.artwork

        async let albumsTask = MusicSearchService.shared.lookupPlexArtistAlbums(
            id: playableContent.content.id
        )
        async let allTask = MusicSearchService.shared.getPlexArtistAllAlbums(
            id: playableContent.content.id
        )
        
        let (albumsResult, (liveResult, singlesResult, othersResult)) = await (albumsTask, allTask)
        
        albums = albumsResult
        allAlbums = albumsResult + liveResult + singlesResult + othersResult
        liveAlbums = liveResult
        singles = singlesResult
        
        albumType = .firstAvailable(albums: albums, live: liveAlbums, singles: singles, all: allAlbums)
        artistContent = playableContent
    }
    
    private func loadPlexArtistData(id: String, setAlbums: Bool) async {
        async let albumsTask = MusicSearchService.shared.lookupPlexArtistAlbums(id: id)
        async let allTask = MusicSearchService.shared.getPlexArtistAllAlbums(id: id)
        async let artistTask = MusicSearchService.shared.lookupPlexArtist(id: id)
        
        let (albumsResult, (liveResult, singlesResult, othersResult), artistResult) = await (
            albumsTask, allTask, artistTask
        )
        
        if setAlbums {
            albums = albumsResult
        }
        allAlbums = albumsResult + liveResult + singlesResult + othersResult
        liveAlbums = liveResult
        singles = singlesResult
        
        if let artistResult {
            artistContent = artistResult
            artworkURL = playableContent.artwork
        }
    }
    
    // MARK: - Helpers
    
    private func sortAlbumsByYear(_ albums: [PlayableContent]) -> [PlayableContent] {
        albums.sorted { album1, album2 in
            let year1 = album1.metadata?.albumYear ?? .now
            let year2 = album2.metadata?.albumYear ?? .now
            return year1 > year2
        }
    }
}

// MARK: - Collapsible Header

private struct CollapsibleHeader<Header: View, Trailing: View>: View {
    let title: String?
    @Binding var isExpanded: Bool
    let showChevron: Bool
    let header: Header
    let trailing: Trailing
    
    init(
        title: String?,
        isExpanded: Binding<Bool>,
        showChevron: Bool = true,
        @ViewBuilder header: () -> Header = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.showChevron = showChevron
        self.header = header()
        self.trailing = trailing()
    }
    
    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack {
                if let title {
                    Text(title)
                        .font(.headline)
#if targetEnvironment(macCatalyst)
                        .foregroundStyle(.foreground)
                        .font(.title2)
#endif
                }
                
                header
                
                Spacer()
                
                trailing
                
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.smooth(duration: 0.3), value: isExpanded)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.white.opacity(0.001))
        .listRowSeparator(.hidden)
    }
}

// MARK: - Preview

#Preview {
    // https://music.apple.com/us/playlist/dua-lipa-essentials/pl.ee7b1aea4b5f42d398e6cd3084f7396b
    // https://music.apple.com/us/album/future-nostalgia-the-moonlight-edition/1551178998
    /// 6M2wZ9GZgrQXHCFfjv46we
    
    NavigationStack {
        ArtistDetailView(playableContent: PlayableContent(
            title: "Dua Lipa",
            subtitle: "",
            thumbnail: URL(string: "https://i.scdn.co/image/ab6761610000e5eb0c68f6c95232e716f0abee8d"),
            artwork: URL(string: "https://i.scdn.co/image/ab6761610000e5eb0c68f6c95232e716f0abee8d"),
            content: MediaContent(
                service: .spotify,
                id: "6M2wZ9GZgrQXHCFfjv46we",
                type: .artist,
                location: nil
            ))
        )
        .withEnvironments()
        .environment(Router())
        .environment(SelectedGroupService())
    }
}
