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
    @Environment(RemoteFeatureFlags.self) private var remoteFlags
    
    let playableContent: PlayableContent
    @State private var tracks: [PlayableContent] = []
    @State private var albums: [PlayableContent] = []
    @State private var liveAlbums: [PlayableContent] = []
    @State private var singles: [PlayableContent] = []
    @State private var allAlbums: [PlayableContent] = []
    @State private var latestRelease: PlayableContent?
    
    @State private var artworkURL: URL?
    @State private var isLoading: Bool = false
    @State private var isLoadingTracks: Bool = true
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
        return artistContent.content.service.supportsRadio
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
        HStack(spacing: 8) {
            if supportsRadio {
                Button {
                    Task { await startRadio() }
                } label: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                }
                .buttonBorderShape(.circle)
                .contentShape(.rect)
                .glassButton()
                .accessibilityLabel("Radio")
                .accessibilityHint("Starts radio playback for this selection")
            }

            if !tracks.isEmpty {
                Button {
                    Task { await playAllTracks(position: .now) }
                } label: {
                    ViewThatFits(in: .horizontal) {
                        Text("Popular \(Image(systemName: "star.fill"))")
                            .minimumScaleFactor(0.7)
                            .padding(.vertical, 4)
                            .foregroundStyle(.white)
                        Image(systemName: "star.fill")
                    }
                }
                .glassButton()
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            if !currentAlbums.isEmpty {
                Button {
                    Task { await playDiscography(position: .next) }
                } label: {
                    Text("Discography \(Image(systemName: "play.fill"))")
                        .minimumScaleFactor(0.7)
                        .padding(.vertical, 4)
                        .foregroundStyle(.white)
                }
                .glassButton()
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            artistActionsMenu
        }
        .animation(.smooth(duration: 0.3), value: tracks.isEmpty)
        .animation(.smooth(duration: 0.3), value: currentAlbums.isEmpty)
        .lineLimit(1)
    }

    private var artistActionsMenu: some View {
        Menu {
            if let artistContent, artistContent.content.location != nil {
                OpenInServiceView(item: artistContent)
            }
            Divider()
            if !tracks.isEmpty {
                Section("Popular Tracks") {
                    Button {
                        Task { await playAllTracks(position: .next) }
                    } label: {
                        Label("Play Next", systemImage: "text.insert")
                    }

                    Button {
                        Task { await playAllTracks(position: .end) }
                    } label: {
                        Label("Play Last", systemImage: "text.append")
                    }

                    Button {
                        Task { await playAllTracks(position: .replace) }
                    } label: {
                        Label("Replace Queue", systemImage: "play.fill")
                    }

                    AddTracksToPlaylistMenu(tracks: tracks)
                }
            }

            if !currentAlbums.isEmpty {
                Section("Discography") {
                    Button {
                        Task { await playDiscography(position: .next) }
                    } label: {
                        Label("Play Next", systemImage: "text.insert")
                    }

                    Button {
                        Task { await playDiscography(position: .end) }
                    } label: {
                        Label("Play Last", systemImage: "text.append")
                    }

                    Button {
                        Task { await playDiscography(position: .replace) }
                    } label: {
                        Label("Replace Queue", systemImage: "play.fill")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
        }
        .buttonBorderShape(.circle)
        .contentShape(.rect)
        .glassButton()
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
        Section {
            CollapsibleHeader(
                title: "Popular",
                isExpanded: $isTopSongsExpanded
            )

            if isTopSongsExpanded {
                if !tracks.isEmpty {
                    ForEach(tracks) { track in
                        PlayableContentView(item: track, hideContentType: true)
                            .listRowBackground(Color.white.opacity(0.001))
                            .listRowSeparator(.hidden)
                    }
                } else if isLoadingTracks {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.regular)
                        Spacer()
                    }
                    .listRowBackground(Color.white.opacity(0.001))
                    .listRowSeparator(.hidden)
                } else {
                    Text("No tracks found")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.white.opacity(0.001))
                        .listRowSeparator(.hidden)
                }
            }
        }
    }
    
    // MARK: - Albums Section
    
    @ViewBuilder
    private var albumsSection: some View {
        if !allAlbums.isEmpty || isLoading || !albums.isEmpty {
            Section {
                CollapsibleHeader(
                    title: "Albums",
                    isExpanded: $isAlbumsExpanded
                )
                if isAlbumsExpanded {
                    if supportsAlbumCategories && !allAlbums.isEmpty {
                        albumCategoryPicker
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
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
    
    private func playAllTracks(position: QueuePosition = .next) async {
        let trackCount = tracks.count
        let queueAllSongs: (GroupRoom) async throws -> Void = { group in
            HapticManager.shared.fireHaptic(.buttonPress)
            switch position {
            case .front:
                alertService.showAlert(with: "Adding \(trackCount) songs to front", imageName: "text.insert")
                try await sonosService.queue(contents: tracks, group: group, position: .front)
            case .next:
                alertService.showAlert(with: "Playing \(trackCount) songs next", imageName: "text.insert")
                try await sonosService.queue(contents: tracks, group: group, position: .next)
            case .end:
                alertService.showAlert(with: "Added \(trackCount) songs to queue", imageName: "text.append")
                try await sonosService.queue(contents: tracks, group: group, position: .end)
            case .now:
                alertService.showAlert(with: "Playing \(trackCount) songs", imageName: "play.fill")
                try await sonosService.playNext(tracks, on: group)
                await sonosService.play(ip: group.coordinatorRoom.ip)
            case .replace:
                alertService.showAlert(with: "Replacing queue with \(trackCount) songs", imageName: "star.fill")
                try await sonosService.queue(contents: tracks, group: group, position: .replace)
                await sonosService.play(ip: group.coordinatorRoom.ip)
            }
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
    
    private func playDiscography(position: QueuePosition = .next) async {
        let albumsToPlay = Array(currentAlbums.reversed())
        let albumCount = albumsToPlay.count
        let queueAll: (GroupRoom) async throws -> Void = { group in
            HapticManager.shared.fireHaptic(.buttonPress)

            switch position {
            case .front:
                alertService.showAlert(with: "Adding \(albumCount) albums to front", imageName: "text.insert")
                try await sonosService.queue(contents: albumsToPlay, group: group, position: .front)
            case .next:
                alertService.showAlert(with: "Playing \(albumCount) albums next", imageName: "text.insert")
                try await sonosService.queue(contents: albumsToPlay, group: group, position: .next)
            case .end:
                alertService.showAlert(with: "Added \(albumCount) albums to queue", imageName: "text.append")
                try await sonosService.queue(contents: albumsToPlay, group: group, position: .end)
            case .now:
                alertService.showAlert(with: "Playing \(albumCount) albums", imageName: "play.fill")
                try await sonosService.playNext(albumsToPlay, on: group)
                await sonosService.play(ip: group.coordinatorRoom.ip)
            case .replace:
                alertService.showAlert(with: "Replacing queue with \(albumCount) albums", imageName: "figure.dance")
                try await sonosService.queue(contents: albumsToPlay, group: group, position: .replace)
                await sonosService.play(ip: group.coordinatorRoom.ip)
            }
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
        case (.artist, .deezer):
            await loadDeezerArtist()
        case (.track, .deezer):
            await loadDeezerTrackArtist()
        case (.album, .deezer):
            await loadDeezerAlbumArtist()
        default:
            break
        }
        isLoading = false
        isLoadingTracks = false
        
        if let artistContent {
            RecentSearchesStorage.shared.addOrMoveToFront(byID: artistContent)
        }
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
            thumbnail: artworkURL,
            artwork: artworkURL,
            content: playableContent.content
        )

        albums = await sonosService.libraryArtist(name: artistName)
        let allTracks = await sonosService.libraryArtist(name: artistName + "/")
        let uniqueTracks = Array(allTracks.uniqued(by: \.title))

        tracks = await popularTracks(for: artistName, from: uniqueTracks)
    }

    private func loadLibraryArtistDirect() async {
        artworkURL = await MusicSearchService.shared.appleLibraryArtistArtwork(name: playableContent.title, size: 500)
        albums = await sonosService.libraryLookup(ID: playableContent.id)
        let allTracks = await sonosService.libraryLookup(ID: playableContent.id + "/")
        let uniqueTracks = Array(allTracks.uniqued(by: \.title))

        tracks = await popularTracks(for: playableContent.title, from: uniqueTracks)
        artistContent = playableContent
    }

    private func popularTracks(for artistName: String, from songs: [PlayableContent]) async -> [PlayableContent] {
        if remoteFlags.isEnabled(.lastFM) {
            let matched = await PopularTracksService.shared.matchLastFM(artistName: artistName, songs: songs)
            if !matched.isEmpty { return matched }
        }
        let matched = await PopularTracksService.shared.matchAppleMusic(artistName: artistName, songs: songs)
        return matched.isEmpty ? Array(songs.prefix(10)) : matched
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
            await loadPlexArtistData(id: artistID)
        } else {
            guard let id = playableContent.id.removingPercentEncoding?.components(separatedBy: ":").last,
                  let artistID = await MusicSearchService.shared.lookupPlexSong(with: id)?.metadata?.artistID
            else { return }

            await loadPlexArtistData(id: artistID)
        }
    }

    private func loadPlexAlbumArtist() async {
        artworkURL = playableContent.artwork

        guard let artistID = playableContent.metadata?.artistID else { return }
        await loadPlexArtistData(id: artistID)
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

        if remoteFlags.isEnabled(.lastFM) {
            let plexTracks = await MusicSearchService.shared.lookupPlexTracks(id: playableContent.content.id)
            tracks = await PopularTracksService.shared.matchLastFM(artistName: playableContent.title, songs: plexTracks)
        }

        albumType = .firstAvailable(albums: albums, live: liveAlbums, singles: singles, all: allAlbums)
        artistContent = playableContent
    }

    private func loadPlexArtistData(id: String) async {
        let artistName = playableContent.metadata?.artist ?? playableContent.title
        async let albumsTask = MusicSearchService.shared.lookupPlexArtistAlbums(id: id)
        async let allTask = MusicSearchService.shared.getPlexArtistAllAlbums(id: id)
        async let artistTask = MusicSearchService.shared.lookupPlexArtist(id: id)

        let (albumsResult, (liveResult, singlesResult, othersResult), artistResult) = await (
            albumsTask, allTask, artistTask
        )

        albums = albumsResult
        allAlbums = albumsResult + liveResult + singlesResult + othersResult
        liveAlbums = liveResult
        singles = singlesResult

        if remoteFlags.isEnabled(.lastFM) {
            let plexTracks = await MusicSearchService.shared.lookupPlexTracks(id: id)
            tracks = await PopularTracksService.shared.matchLastFM(artistName: artistName, songs: plexTracks)
        }

        albumType = .firstAvailable(albums: albums, live: liveAlbums, singles: singles, all: allAlbums)

        if let artistResult {
            artistContent = artistResult
            artworkURL = playableContent.artwork
        }
    }
    
    // MARK: - Deezer Loading

    private func loadDeezerArtist() async {
        artworkURL = playableContent.artwork
        artistContent = playableContent
        async let topTracks = MusicSearchService.shared.lookupDeezerArtistTopTracks(id: playableContent.content.id)
        async let artistAlbums = MusicSearchService.shared.lookupDeezerArtistAlbums(id: playableContent.content.id)
        tracks = await topTracks
        albums = await artistAlbums
    }

    private func loadDeezerTrackArtist() async {
        let artistID: String?
        if let existing = playableContent.metadata?.artistID {
            artistID = existing
        } else {
            artistID = await MusicSearchService.shared.lookupDeezerTrack(with: playableContent.content.id)?.metadata?.artistID
        }
        guard let artistID else {
            artworkURL = playableContent.artwork
            artistContent = playableContent
            return
        }
        await loadDeezerArtistData(id: artistID)
    }

    private func loadDeezerAlbumArtist() async {
        guard let artistID = playableContent.metadata?.artistID else {
            artworkURL = playableContent.artwork
            artistContent = playableContent
            return
        }
        await loadDeezerArtistData(id: artistID)
    }

    private func loadDeezerArtistData(id: String) async {
        async let artist = MusicSearchService.shared.lookupDeezerArtist(id: id)
        async let topTracks = MusicSearchService.shared.lookupDeezerArtistTopTracks(id: id)
        async let artistAlbums = MusicSearchService.shared.lookupDeezerArtistAlbums(id: id)
        if let artistResult = await artist {
            artistContent = artistResult
            artworkURL = artistResult.artwork
        }
        tracks = await topTracks
        albums = await artistAlbums
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
