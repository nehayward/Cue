import CloudStorage
import Defaults
import MusicKit
import MusicSearchKit
import Nuke
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
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Defaults.AppStorageKeys.defaultPlayAction) private var replaceQueueByDefault: Bool = false
    
    let playableContent: PlayableContent
    @State private var tracks: [PlayableContent] = []
    @State private var albums: [PlayableContent] = []
    @State private var liveAlbums: [PlayableContent] = []
    @State private var singles: [PlayableContent] = []
    @State private var compilations: [PlayableContent] = []
    @State private var allAlbums: [PlayableContent] = []
    @State private var latestRelease: PlayableContent?
    
    @State private var artworkURL: URL?
    @State private var isLoading: Bool = false
    /// The page's artist read whole (`loadArtistData`).
    @State private var hasLoaded = false
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
    
    private func releases(of category: AlbumCategory) -> [PlayableContent] {
        switch category {
        case .albums: albums
        case .singles: singles
        case .live: liveAlbums
        case .compilations: compilations
        case .all: allAlbums
        }
    }

    private var currentAlbums: [PlayableContent] {
        releases(of: albumType)
    }

    /// What Discography plays, whatever kind the chips show: the artist's
    /// albums, else the first kind they have (an artist with only singles).
    private var discography: [PlayableContent] {
        AlbumCategory.allCases.lazy.map(releases(of:)).first { !$0.isEmpty } ?? []
    }
    
    /// An artist of the on-device library (`OnDeviceLibrary`): their songs
    /// and albums here, read from the device, so the page opens with no
    /// network and keeps up as downloads come and go. No server is asked,
    /// so no radio, latest release or album kinds.
    private var isOnDevice: Bool {
        OnDeviceLibrary.isContainer(playableContent)
    }

    private var supportsRadio: Bool {
        guard let artistContent, !isOnDevice else { return false }
        return artistContent.content.service.supportsRadio
            && artistContent.content.type != .libraryArtist
    }

    /// Whether the albums come in kinds (chips over them): from the page's
    /// own content until the artist is in, so the chips are there from the
    /// first draw rather than a title first.
    private var supportsAlbumCategories: Bool {
        guard !isOnDevice else { return false }
        return [.apple, .plex].contains((artistContent ?? playableContent).content.service)
    }
    
    // MARK: - Body

    /// The author's page for an artist opened from a book or a book's file
    /// (the player's artist line on a book): their books, not an artist's
    /// popular songs. It stays theirs while the book is the one loaded or
    /// the one last left (`AudiobookPlayer.book(containing:)`).
    var body: some View {
        if let author = AudiobookAuthor(for: playableContent) {
            AudiobookAuthorView(author: author)
        } else {
            artistPage
        }
    }

    private var artistPage: some View {
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
        .onChange(of: isOnDevice ? OnDeviceLibrary.changeToken : 0) {
            loadOnDevice()
        }
    }
    
    // MARK: - Artwork Section
    
    /// The hero image, decoded no larger than it is drawn. The header shows
    /// at most ~400pt and blurs it, but the URL is the full-size art — for
    /// Plex the original file, often several megapixels — and a 100pt blur
    /// over a bitmap that size costs Core Animation offscreen buffers many
    /// times the image, which is where this screen's memory jumps came from.
    private var heroRequest: ImageRequest {
        var request = ImageRequest(url: artworkURL)
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 800)
        return request
    }

    @ViewBuilder
    private var artworkSection: some View {
        Color.clear.overlay {
            // One image for the glow and the picture, so both land in the
            // same frame, as on an album's page.
            LazyImage(request: heroRequest.withBlurredFoot) { phase in
                if let image = phase.image {
                    ZStack {
                        image
                            .resizable()
                            .scaledToFit()
                            .blur(radius: 100)
                            .frame(maxWidth: .infinity, maxHeight: maxHeight)
                        image
                            .resizable()
                            .scaledToFill()
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
    
    @ViewBuilder
    private var radioButtonOverlay: some View {
        if isOnDevice {
            onDeviceButtons
        } else {
            serverButtons
        }
    }

    /// Play and Shuffle across the artist's songs here, and the filled
    /// download button with Remove behind it, as a downloaded album's page
    /// has.
    private var onDeviceButtons: some View {
        HStack(spacing: 12) {
            Button {
                playOnDevice(shuffle: false)
            } label: {
                Text("\(Image(systemName: "play.fill")) Play")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .glassButton()
            .foregroundStyle(.primary)
            Button {
                playOnDevice(shuffle: true)
            } label: {
                Text("\(Image(systemName: "shuffle")) Shuffle")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .glassButton()
            .foregroundStyle(.primary)
            OnDeviceDownloadButton(container: playableContent)
        }
        .bold()
        .fontDesign(.rounded)
        // Dark glass in Light Mode too, as on an album's page.
        .environment(\.colorScheme, .dark)
    }

    private var serverButtons: some View {
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

            if !discography.isEmpty {
                Button {
                    // The headline action starts the discography fresh —
                    // clear the queue, then every album oldest-first. The
                    // ellipsis menu still offers play next / last.
                    Task { await playDiscography(position: .replace) }
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
        .animation(.smooth(duration: 0.3), value: discography.isEmpty)
        .lineLimit(1)
        // Dark glass in Light Mode too, as on an album's page.
        .environment(\.colorScheme, .dark)
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

                    // Sonos playlists only.
                    if sonosService.isAvailable {
                        AddTracksToPlaylistMenu(tracks: tracks)
                    }
                }
            }

            if !discography.isEmpty {
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
                title: isOnDevice ? "Songs" : "Popular",
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
        if isLoading || AlbumCategory.allCases.contains(where: { !releases(of: $0).isEmpty }) {
            Section {
                // The kinds' chips head the section, in the title's place,
                // with its chevron, where there are kinds to choose; else the
                // title.
                if supportsAlbumCategories {
                    // No background of its own, as the rows under it.
                    AlbumKindPicker(kinds: shownKinds, selection: $albumType, isExpanded: $isAlbumsExpanded)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.white.opacity(0.001))
                        .listRowSeparator(.hidden)
                } else {
                    CollapsibleHeader(
                        title: "Albums",
                        isExpanded: $isAlbumsExpanded
                    )
                }
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
                }
            }
        }
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

        let radioContent = artistContent.toRadio
        let onSpeaker: (GroupRoom) async throws -> Void = { group in
            do {
                alertService.showAlertContent(with: radioContent, subtitle: "Radio")
                try await sonosService.startRadio(content: radioContent, group: group)
                playHistoryService.record(radioContent)
            } catch {
                alertService.showAlert(
                    with: "Please authorize \(artistContent.content.service.title) in Sonos",
                    imageName: "exclamationmark.triangle.fill"
                )
            }
        }

        HapticManager.shared.fireHaptic(.buttonPress)
        // The speaker this screen was opened for plays Sonos' radio. Otherwise
        // the remembered destination decides: a speaker, or Apple Music's
        // artist station on this device.
        if let group = selectedGroupService.group {
            try? await onSpeaker(group)
            return
        }
        await PlayDestinationRouter.playRadio(from: artistContent, onGroup: onSpeaker)
    }
    
    private func playAllTracks(position: QueuePosition = .next) async {
        let trackCount = tracks.count
        let queueAllSongs: (GroupRoom, QueuePosition) async throws -> Void = { group, position in
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
            // No one container to stand for a run of an artist's tracks —
            // the artist is what it was played from.
            await PlayDestinationRouter.play(tracks, position: position, from: artistContent, queue: queueAllSongs)
            return
        }

        try? await queueAllSongs(group, position)
    }
    
    private func playDiscography(position: QueuePosition = .next) async {
        let albumsToPlay = Array(discography.reversed())
        let albumCount = albumsToPlay.count
        let queueAll: (GroupRoom, QueuePosition) async throws -> Void = { group, position in
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
                // startIndex 0: playback begins as soon as the first item
                // lands instead of waiting for the whole discography to fill.
                try await sonosService.queue(contents: albumsToPlay, group: group, position: .replace, startIndex: 0)
            }
        }

        guard let group = selectedGroupService.group else {
            await PlayDestinationRouter.play(albumsToPlay, position: position, from: artistContent, queue: queueAll)
            return
        }

        try? await queueAll(group, position)
    }
    
    // MARK: - Data Loading
    
    /// Plays the artist's songs here as one container, as an on-device
    /// album's page plays its own.
    private func playOnDevice(shuffle: Bool) {
        HapticManager.shared.fireHaptic(.buttonPress)
        let container = playableContent
        let total = tracks.count
        Task { @MainActor in
            let position = QueuePosition.defaultPosition(for: container.content.type, replaceQueueByDefault: replaceQueueByDefault)
            let playMode: PlayMode = shuffle ? [.normal, .shuffle] : .normal
            let queue: (GroupRoom, QueuePosition) async throws -> Void = { group, selectedPosition in
                await SonosService.shared.setPlayMode(group.ip, mode: playMode)
                group.playMode = playMode
                QueueManager.shared.addToQueue(
                    item: QueueItem(playableContent: container, group: group, position: selectedPosition, total: total, showBanner: false)
                )
                Router.main.show(destination: .player(groupID: group.coordinatorID))
            }
            guard let group = selectedGroupService.group else {
                await PlayDestinationRouter.play(container, position: position, shuffle: shuffle, queue: queue)
                return
            }
            try? await queue(group, position)
        }
    }

    /// The artist's songs and albums here, from the device. Goes back once
    /// they're all gone.
    private func loadOnDevice() {
        guard isOnDevice else { return }
        let hadTracks = !tracks.isEmpty
        artistContent = playableContent
        artworkURL = playableContent.artwork ?? playableContent.thumbnail
        tracks = OnDeviceLibrary.tracks(inContainer: playableContent) ?? []
        albums = OnDeviceLibrary.albums(ofArtist: playableContent).map(\.container)
        allAlbums = albums
        isLoadingTracks = false
        isLoading = false
        if hadTracks, tracks.isEmpty {
            dismiss()
        }
    }

    private func loadArtistData() async {
        if isOnDevice {
            loadOnDevice()
            return
        }
        // Once: the task runs again as the page comes back from an album
        // pushed over it, which read every kind again and put the chips
        // back on the first.
        guard !hasLoaded else { return }
        isLoading = true

        // If already an artist type, set immediately (no spinner needed)
        if playableContent.content.type == .artist || playableContent.content.type == .libraryArtist {
            artistContent = playableContent
        }

        switch (playableContent.content.type, playableContent.content.service) {
        case (.artist, .apple):
            await loadAppleArtist(id: playableContent.content.id)
        case (.libraryArtist, .apple):
            await loadAppleLibraryArtist()
        case (.artist, .spotify):
            await loadSpotifyArtist()
        case (.track, .apple):
            await loadAppleTrackArtist()
        case (.libraryTrack, .apple):
            await loadAppleLibraryTrackArtist()
            // The library song's catalog link goes through the web API's
            // library ids, which a song from MusicKit doesn't have.
            if artistContent == nil {
                await loadAppleArtist(named: playableContent.metadata?.artist)
            }
        case (.libraryAlbum, .apple):
            // The artist line on a library album. The album carries only the
            // artist's name, so it's found in the catalog by that.
            await loadAppleArtist(named: playableContent.metadata?.artist)
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
        case (.artist, .subsonic):
            await loadSubsonicArtistData(id: playableContent.content.id)
        case (.track, .subsonic), (.album, .subsonic):
            await loadSubsonicTrackOrAlbumArtist()
        case (.artist, .files):
            await loadFilesArtist(id: playableContent.content.id)
        case (.track, .files), (.album, .files):
            await FilesLibraryService.shared.scanIfNeeded()
            let files = FilesLibraryService.shared
            let artistID = playableContent.metadata?.artistID
                ?? files.track(id: playableContent.content.id)?.metadata?.artistID
                ?? files.album(id: playableContent.content.id)?.metadata?.artistID
            if let artistID {
                await loadFilesArtist(id: artistID)
            }
        default:
            break
        }
        isLoading = false
        isLoadingTracks = false
        // Left partway (a pushed page cancels the task), it reads again.
        hasLoaded = !Task.isCancelled

        if let artistContent {
            RecentSearchesStorage.shared.addOrMoveToFront(byID: artistContent)
        }
    }

    // MARK: - Apple Music Loading
    
    /// The catalog artist `id`. `false` when the catalog has no such artist,
    /// so a library artist can fall back to what the library holds.
    @discardableResult
    private func loadAppleArtist(id: String) async -> Bool {
        guard let artist: Artist = try? await MusicSearchService.shared.lookup(
            id: id
        ) else { return false }
        
        guard let topTracks = artist.topSongs, let artistAlbums = artist.albums else { return false }
        
        tracks = topTracks.map(\.toPlayable)
        artworkURL = artist.artwork?.url(width: 500, height: 500)

        // The artist itself is in hand from here: whatever else fails, the
        // page shows it.
        artistContent = artist.toPlayable
        if await !loadAppleAlbumKinds(artistID: id) {
            albums = sortAlbumsByYear(artistAlbums.map(\.toPlayable).filter { !($0.metadata?.isSingle ?? false) })
        }

        guard let allArtist: Artist = try? await MusicSearchService.shared.artistCatalog(
            id: id
        ) else { return true }
        
        latestRelease = allArtist.latestRelease?.toPlayable
        
        if let live = allArtist.liveAlbums {
            if liveAlbums.isEmpty {
                liveAlbums = sortAlbumsByYear(live.map(\.toPlayable))
            }
        }
        
        artworkURL = artist.artwork?.url(width: 500, height: 500)
        artistContent = artist.toPlayable
        
        if let all: [PlayableContent] = try? await MusicSearchService.shared.allAlbums(
            id: id
        ) {
            allAlbums = Self.merged(allAlbums, all)
        }
        return true
    }
    
    /// The artist's albums, singles and EPs, live albums and compilations,
    /// as Apple Music's artist page shelves them, the albums each once
    /// (`eachAlbumOnce`). False when the catalog didn't answer, for the
    /// caller's albums to stand.
    private func loadAppleAlbumKinds(artistID: String) async -> Bool {
        guard let kinds = await MusicSearchService.shared.artistAlbumKinds(id: artistID),
              !kinds.albums.isEmpty || !kinds.singles.isEmpty else { return false }
        albums = Self.eachAlbumOnce(kinds.albums)
        singles = sortAlbumsByYear(kinds.singles)
        liveAlbums = sortAlbumsByYear(kinds.live)
        compilations = sortAlbumsByYear(kinds.compilations)
        allAlbums = Self.merged(allAlbums, sortAlbumsByYear(kinds.albums + kinds.singles + kinds.live + kinds.compilations))
        chooseKindIfEmpty()
        return true
    }

    /// The kind first available, only when the one chosen has nothing: a
    /// kind chosen stays chosen as later answers come in, or as the page
    /// loads again on coming back to it.
    private func chooseKindIfEmpty() {
        guard releases(of: albumType).isEmpty else { return }
        albumType = .firstAvailable(albums: albums, live: liveAlbums, singles: singles, compilations: compilations, all: allAlbums)
    }

    /// The kinds with releases, the chips shown; the chosen one with them
    /// only while none have any (loading).
    private var shownKinds: [AlbumCategory] {
        let kinds = AlbumCategory.allCases.filter { !releases(of: $0).isEmpty }
        return kinds.isEmpty ? [albumType] : kinds
    }

    /// `all` with `more` that it lacks, newest first, each once.
    private static func merged(_ all: [PlayableContent], _ more: [PlayableContent]) -> [PlayableContent] {
        var seen = Set(all.map(\.id))
        let added = all + more.filter { seen.insert($0.id).inserted }
        return added.sorted { ($0.metadata?.albumYear ?? .distantPast) > ($1.metadata?.albumYear ?? .distantPast) }
    }

    /// Each album once, by its plain title, newest first: the discography
    /// widget's rules (`AlbumEditions`), so the page's Albums and the
    /// widget's list the same albums.
    private static func eachAlbumOnce(_ albums: [PlayableContent]) -> [PlayableContent] {
        AlbumEditions.albums(albums, title: \.title, released: { $0.metadata?.albumYear })
            .map { album in
                let item = album.item
                return PlayableContent(title: album.title, subtitle: item.subtitle, thumbnail: item.thumbnail, artwork: item.artwork, content: item.content, previewURL: item.previewURL, metadata: item.metadata)
            }
    }

    private func loadAppleLibraryArtist() async {
        // The Apple Music artist, when the catalog has one: top songs, every
        // album, the latest release — not just the few albums in the
        // library, which is all this page could show before and often
        // didn't load at all.
        if let catalogID = await catalogArtistID(), await loadAppleArtist(id: catalogID) {
            return
        }

        if let url = await MusicSearchService.shared.appleLibraryArtistArtwork(name: playableContent.title, size: 500) {
            artworkURL = url
        }
        
        if let libraryAlbums = await MusicSearchService.shared.appleLibraryArtistAlbumLookup(id: playableContent.content.id) {
            albums = libraryAlbums.data.compactMap(\.toPlayable)
        }
        
        artistContent = playableContent
    }
    
    /// The catalog id behind a library artist: the library's own link to
    /// the catalog, else an artist of exactly that name in a catalog search.
    private func catalogArtistID() async -> String? {
        if let linked = await MusicSearchService.shared.appleLibraryArtistLookup(id: playableContent.content.id)?.data.first?.id {
            return linked
        }
        return await catalogArtistID(named: playableContent.title)
    }

    /// An Apple Music artist named exactly `name`, from a catalog search.
    private func catalogArtistID(named name: String) async -> String? {
        var request = MusicCatalogSearchRequest(term: name, types: [Artist.self])
        request.limit = 5
        guard let results = try? await request.response() else { return nil }
        let wanted = name.lowercased()
        return results.artists.first { $0.name.lowercased() == wanted }?.id.rawValue
    }

    /// The Apple Music artist called `name`, for library items that carry
    /// only a name.
    private func loadAppleArtist(named name: String?) async {
        guard let name, !name.isEmpty, let id = await catalogArtistID(named: name) else { return }
        await loadAppleArtist(id: id)
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
        if await !loadAppleAlbumKinds(artistID: artistID) {
            albums = sortAlbumsByYear(artistAlbums.map(\.toPlayable).filter { !($0.metadata?.isSingle ?? false) })
        }
        
        if let live = allArtist.liveAlbums {
            if liveAlbums.isEmpty {
                liveAlbums = sortAlbumsByYear(live.map(\.toPlayable))
            }
        }
        
        artworkURL = artist.artwork?.url(width: 500, height: 500)
        artistContent = artist.toPlayable
        
        if let all: [PlayableContent] = try? await MusicSearchService.shared.allAlbums(id: artistID) {
            allAlbums = Self.merged(allAlbums, all)
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
        if await !loadAppleAlbumKinds(artistID: artistID) {
            albums = artistAlbums.map(\.toPlayable)
        }
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
        if await !loadAppleAlbumKinds(artistID: artistID) {
            albums = sortAlbumsByYear(artistAlbums.map(\.toPlayable).filter { !($0.metadata?.isSingle ?? false) })
        }

        if let live = artist.liveAlbums {
            if liveAlbums.isEmpty {
                liveAlbums = sortAlbumsByYear(live.map(\.toPlayable))
            }
        }

        artworkURL = artist.artwork?.url(width: 500, height: 500)
        artistContent = artist.toPlayable

        if let all: [PlayableContent] = try? await MusicSearchService.shared.allAlbums(id: artistID) {
            allAlbums = Self.merged(allAlbums, all)
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

        albums = Self.eachAlbumOnce(albumsResult)
        allAlbums = albumsResult + liveResult + singlesResult + othersResult
        liveAlbums = liveResult
        singles = singlesResult
        // Plex's soundtracks, compilations and demos.
        compilations = othersResult

        if remoteFlags.isEnabled(.lastFM) {
            let plexTracks = await MusicSearchService.shared.lookupPlexTracks(id: playableContent.content.id)
            tracks = await PopularTracksService.shared.matchLastFM(artistName: playableContent.title, songs: plexTracks)
        }

        chooseKindIfEmpty()
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

        albums = Self.eachAlbumOnce(albumsResult)
        allAlbums = albumsResult + liveResult + singlesResult + othersResult
        liveAlbums = liveResult
        singles = singlesResult
        // Plex's soundtracks, compilations and demos.
        compilations = othersResult

        if remoteFlags.isEnabled(.lastFM) {
            let plexTracks = await MusicSearchService.shared.lookupPlexTracks(id: id)
            tracks = await PopularTracksService.shared.matchLastFM(artistName: artistName, songs: plexTracks)
        }

        chooseKindIfEmpty()

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

    // MARK: - Subsonic Loading

    private func loadSubsonicTrackOrAlbumArtist() async {
        let artistID: String?
        if let existing = playableContent.metadata?.artistID {
            artistID = existing
        } else if playableContent.content.type.isTrack {
            artistID = await MusicSearchService.shared.lookupSubsonicTrack(with: playableContent.content.id)?.metadata?.artistID
        } else {
            artistID = await MusicSearchService.shared.lookupSubsonicAlbum(with: playableContent.content.id)?.metadata?.artistID
        }
        guard let artistID else {
            artworkURL = playableContent.artwork
            artistContent = playableContent
            return
        }
        await loadSubsonicArtistData(id: artistID)
    }

    private func loadSubsonicArtistData(id: String) async {
        // One getArtist response carries the artist and their albums. Sorted
        // newest-first like the other services — Discography reverses this
        // for oldest-first playback.
        if let result = await MusicSearchService.shared.lookupSubsonicArtistWithAlbums(id: id) {
            artistContent = result.artist
            artworkURL = result.artist.artwork
            albums = sortAlbumsByYear(result.albums)
        }
        // Top songs are keyed by artist name; servers without play data
        // return nothing and the section just stays hidden.
        let artistName = artistContent?.title ?? playableContent.metadata?.artist ?? ""
        if !artistName.isEmpty {
            tracks = await MusicSearchService.shared.subsonicArtistTopSongs(artistName: artistName)
        }
    }

    /// Everything comes from the folder's index: the artist, their albums,
    /// and every song as the "top" list, since files carry no play counts.
    private func loadFilesArtist(id: String) async {
        let files = FilesLibraryService.shared
        await files.scanIfNeeded()
        guard let artist = files.artist(id: id) else { return }
        artistContent = artist
        artworkURL = artist.artwork
        albums = files.artistAlbums(artistID: id)
        tracks = Array(files.artistTracks(artistID: id).prefix(25))
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

// MARK: - Album kinds

/// The kinds of release, as Apple Music's artist page shelves them.
/// Albums are each album once (`AlbumEditions`), as the discography
/// widget's Albums lists them.
fileprivate enum AlbumCategory: Int, CaseIterable {
    case albums = 0
    case singles = 1
    case live = 2
    case compilations = 3
    case all = 4

    var title: String {
        switch self {
        case .albums: "Albums"
        case .singles: "Singles & EPs"
        case .live: "Live"
        case .compilations: "Compilations"
        case .all: "All"
        }
    }

    static func firstAvailable(
        albums: [PlayableContent],
        live: [PlayableContent],
        singles: [PlayableContent],
        compilations: [PlayableContent] = [],
        all: [PlayableContent]
    ) -> AlbumCategory {
        let availability: [(AlbumCategory, Bool)] = [
            (.albums, !albums.isEmpty),
            (.singles, !singles.isEmpty),
            (.live, !live.isEmpty),
            (.compilations, !compilations.isEmpty),
            (.all, !all.isEmpty)
        ]

        return availability.first(where: { $0.1 })?.0 ?? .all
    }
}

/// The kinds the artist has releases of, as chips in a row that scrolls
/// sideways: five don't fit a segmented control at an iPhone's width. A
/// change animates as the system's segmented control does: one pill slides
/// to the chosen chip, its words in the background's colour showing only
/// through the pill, so nothing flips colour at once; the rows below fade
/// over, the list easing to its new length rather than jumping, and the
/// chosen chip is scrolled into view.
///
/// Off the page, and in parts that are views of their own rather than
/// builder functions, which run with whatever body holds them: a chip
/// measuring itself redraws the row, not the page, and a part whose inputs
/// didn't change isn't drawn again.
fileprivate struct AlbumKindPicker: View {
    let kinds: [AlbumCategory]
    @Binding var selection: AlbumCategory
    @Binding var isExpanded: Bool

    /// Each chip where it is in the row, for the pill.
    @State private var frames: [AlbumCategory: CGRect] = [:]

    var body: some View {
        let pill = kinds.contains(selection) ? frames[selection] : nil
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    AlbumKindChips(kinds: kinds, selection: selection, frames: $frames) { category in
                        withAnimation(.snappy(duration: 0.32)) {
                            selection = category
                            if !isExpanded {
                                isExpanded = true
                            }
                            proxy.scrollTo(category, anchor: .center)
                        }
                    }
                    .coordinateSpace(.named(AlbumKindChips.row))
                    .overlay(alignment: .topLeading) {
                        AlbumKindPill(frame: pill)
                            .foregroundStyle(.primary)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .topLeading) {
                        AlbumKindTitles(kinds: kinds)
                            .foregroundStyle(.background)
                            .mask(alignment: .topLeading) { AlbumKindPill(frame: pill) }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 4)
                }
                // From the screen's edge, the row's inset a margin inside it,
                // so the first chip stands whole where the titles start and
                // chips scroll out under a fade, not cut at the inset.
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollIndicators(.hidden)
                .mask {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 16)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 20)
                    }
                }
            }
            AlbumsCollapseButton(isExpanded: $isExpanded)
        }
    }
}

/// The chips to tap, each measuring where it is in the row for the pill.
fileprivate struct AlbumKindChips: View {
    /// The row's own space, which the pill is placed in.
    static let row = "album kinds"

    let kinds: [AlbumCategory]
    let selection: AlbumCategory
    @Binding var frames: [AlbumCategory: CGRect]
    let choose: (AlbumCategory) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(kinds, id: \.self) { category in
                Button {
                    choose(category)
                } label: {
                    AlbumKindTitle(category: category)
                        .foregroundStyle(.primary)
                        .background(.fill.tertiary, in: .capsule)
                }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.row)) } action: { frame in
                    if frames[category] != frame {
                        frames[category] = frame
                    }
                }
                .id(category)
                .accessibilityAddTraits(category == selection ? .isSelected : [])
            }
        }
    }
}

/// The pill under the chosen chip, where the chip measured itself in the
/// row: it moves only as the kind changes, and rides with the row as the
/// list moves it (a pill matched by `matchedGeometryEffect` stretched as the
/// Popular section above folded).
fileprivate struct AlbumKindPill: View {
    let frame: CGRect?

    var body: some View {
        if let frame {
            Capsule()
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }
    }
}

/// The chips' titles laid out as the chips are, for the pill's words.
fileprivate struct AlbumKindTitles: View {
    let kinds: [AlbumCategory]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(kinds, id: \.self) { category in
                AlbumKindTitle(category: category)
            }
        }
    }
}

fileprivate struct AlbumKindTitle: View {
    let category: AlbumCategory

    var body: some View {
        Text(category.title)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
    }
}

/// Folds the albums away, as the section's title did, its glyph where the
/// Popular title's is.
fileprivate struct AlbumsCollapseButton: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.smooth(duration: 0.3), value: isExpanded)
                .frame(width: 32, height: 32, alignment: .trailing)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .accessibilityLabel(isExpanded ? "Hide Albums" : "Show Albums")
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
