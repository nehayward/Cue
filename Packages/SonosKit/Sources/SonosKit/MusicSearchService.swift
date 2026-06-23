import Foundation
import MusicKit
import MusicSearchKit

@MainActor
@Observable
public final class MusicSearchService {
    public static var shared = MusicSearchService()

    public var query: String = "" {
        didSet {
            if _query.isEmpty {
                suggestions.removeAll()
            }
        }
    }
    
    public var appleMusicAuthorizationStatus: AppleMusicAuthorization = .denied
    
    public var isPlexAuthorized: Bool {
        plex.isAuthorized
    }

    public var plexServerID: String? {
        get {
            plex.serverID
        } set {
            plex.serverID = newValue
        }
    }
    
    public var plexLibrarySelectionID: String? {
        get {
            plex.librarySelectionID
        } set {
            plex.librarySelectionID = newValue
        }
    }

    public var plexConnectionPreference: PlexAPI.ConnectionPreference {
        get {
            plex.connectionPreference
        } set {
            plex.connectionPreference = newValue
        }
    }

    private let appleMusicSearchAPI = AppleMusicSearchAPI()
    private let apple = AppleMusicAPI.shared
    private let plex = PlexAPI.shared
    private let tidal = TidalAPI()
    private let spotifySearchAPI = SpotifyAPI(tokenRefreshHandler: KeychainTokenRefreshHandler.shared)
    private let spotifyLookupAPI = SpotifySonosAPI(tokenRefreshHandler: KeychainTokenRefreshHandler.shared)
    private let tuneIn = TuneInAPI()
    private let sonosService = SonosService.shared

    private let soundCloud = SoundCloudAPI(
        clientId: "iJ161hwUtTqVKptbddkz1NWBYpQDDIcl",
        clientSecret: "zCcBaeVvBKX4R0eAwypLes8PmBknZnqI",
        tokenRefreshHandler: KeychainTokenRefreshHandler.shared
    )
    private let deezer = DeezerAPI()

    private var searchSuggestionTask = Task<([MusicCatalogSearchSuggestionsResponse.Suggestion], MusicItemCollection<MusicCatalogSearchSuggestionsResponse.TopResult>)?, Never> { nil }

    private let debounceDuration: Duration = .milliseconds(150)

    public var suggestions: [MusicCatalogSearchSuggestionsResponse.Suggestion] = []

    public var results: [PlayableContent] = []
    public var newReleases: [SpotifyAlbumItem] = []

    public init() {
        print(#file, #function)
    }

    public func search(for providers: Set<MediaSearchService>) async {
        if query.isEmpty {
            results = []
            return
        }

        let capturedQuery = query
        searchSuggestionTask.cancel()
        searchSuggestionTask = Task { [weak self] in
            guard let self else { return nil }
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return nil }
            let results = await searchSuggestion(query: capturedQuery)
            return results
        }

        await withTaskGroup(of: (MediaSearchService, [PlayableContent]?).self) { group in
            for provider in providers {
                group.addTask { [weak self] in
                    guard let self else { return (provider, nil) }
                    try? await Task.sleep(for: self.debounceDuration)
                    guard !Task.isCancelled else { return (provider, nil) }

                    let fetched: [PlayableContent]?
                    switch provider {
                    case .apple:
                        fetched = await self.searchApple(query: capturedQuery)
                    case .spotify:
                        fetched = await self.searchSpotify(query: capturedQuery)
                    case .library:
                        let playableContent = await self.sonosService.librarySearch(query: capturedQuery)
                        fetched = await self.sortContentByIntelligentSearch(playableContent: playableContent, query: capturedQuery)
                    case .plex:
                        fetched = await self.searchPlex(query: capturedQuery)
                    case .tidal:
                        fetched = await self.searchTidal(query: capturedQuery)
                    case .tuneIn:
                        fetched = await self.searchTuneIn(query: capturedQuery)
                    case .soundcloud:
                        fetched = await self.searchSoundCloud(query: capturedQuery)
                    case .deezer:
                        fetched = await self.searchDeezer(query: capturedQuery)
                    }
                    // If we were cancelled during the fetch, the API may have returned []
                    // for a cancelled URLSession call. Drop the result so we don't blank
                    // out the UI or stomp on the next search's results.
                    if Task.isCancelled { return (provider, nil) }
                    return (provider, fetched)
                }
            }

            for await (provider, providerResults) in group {
                // Parent (this search call) was cancelled — anything still draining out
                // of the group is stale, do not write it.
                if Task.isCancelled { continue }
                // The user may have edited the query while we were awaiting; the new
                // search() call will handle the fresh query, so drop these.
                if self.query != capturedQuery { continue }
                guard let providerResults else { continue }
                if provider == .tuneIn {
                    self.suggestions.removeAll()
                }
                self.results = providerResults
            }
        }

        if Task.isCancelled { return }
        if self.query != capturedQuery { return }

        if let suggestionResults = await searchSuggestionTask.value {
            if !providers.contains(.tuneIn) {
                suggestions = suggestionResults.0
            }
        }
    }

    // Convenience methods for single provider and array of providers
    public func search(for provider: MediaSearchService) async {
        await search(for: [provider])
    }

    public func search(for providers: [MediaSearchService]) async {
        await search(for: Set(providers))
    }
    
    public func searchSuggestion(query: String) async -> ([MusicCatalogSearchSuggestionsResponse.Suggestion],
                                                          MusicItemCollection<MusicCatalogSearchSuggestionsResponse.TopResult>)? {
        if query.isEmpty { return ([], []) }
        guard await requestMusicAuthorization() else { return ([], []) }

        var request = MusicCatalogSearchSuggestionsRequest(term: query, includingTopResultsOfTypes: [Song.self, Album.self, Artist.self, Playlist.self])
        request.limit = 10
        do {
            let response = try await request.response()
            return (response.suggestions, response.topResults)
        } catch {
            return nil
        }
    }

    public func search(song: String, artist: String, album: String) async -> [ItunesResult] {
        await appleMusicSearchAPI.search(for: "\(song) \(artist) \(album)")
    }

    public func appleLookup(id: String) async -> ItunesResult? {
        await appleMusicSearchAPI.lookupTrack(id: id)
    }

    public func spotifyNewReleases() async -> SpotifyResult? {
        await spotifySearchAPI.newReleases()
    }

    public func searchSpotify(song: String, artist: String) async -> SpotifyResult? {
        await spotifySearchAPI.search(for: "\(song) \(artist)", types: [.playlist])
    }

    public func searchSpotifySong(song: String, artist: String) async -> SpotifyResult? {
        await spotifySearchAPI.searchSong(for: "\(song) \(artist)")
    }

    public func spotifyTrackLookup(id: String) async -> SpotifyTrackItem? {
        await spotifySearchAPI.lookupTrack(id: id)
    }

    public func spotifyPlaylistLookup(id: String) async -> SpotifyPlaylistItems? {
        await spotifySearchAPI.playlist(id: id)
    }
    
    public func spotifyPlaylistTracks(id: String, offset: Int = 0) async -> SpotifyPlaylistsFullContainer? {
        await spotifySearchAPI.playlistTracks(id: id, offset: offset)
    }

    public func spotifyAlbumLookup(id: String) async -> SpotifyAlbumItem? {
        await spotifySearchAPI.album(id: id)
    }

    public func spotifyAlbumTracksLookup(id: String, offset: Int = 0, limit: Int = 100) async -> SpotifyAlbumDetails? {
        await spotifySearchAPI.albumDetails(id: id, offset: offset, limit: limit)
    }

    public func spotifyPlaylist(id: String) async -> SpotifyPlaylistItems? {
        await spotifySearchAPI.playlist(id: id)
    }

    public func spotifyArtist(id: String) async -> SpotifyArtistsItems? {
        await spotifySearchAPI.artist(id: id)
    }

    public func spotifyArtistAlbums(id: String) async -> SpotifyArtistAlbums? {
        await spotifySearchAPI.artistAlbums(id: id)
    }

    public func spotifyArtistTopTracks(id: String) async -> [SpotifyTrackItem] {
        await spotifySearchAPI.artistTopTracks(id: id)
    }
    
    public func spotifyGetPlaylists(offset: Int = 0) async -> SpotifyPlaylistResponse? {
        guard let playlists = try? await spotifyLookupAPI.getPlaylists(index: offset) else {
            return nil
        }
        return playlists
    }
    
    public func spotifyGetLikedSongs(offset: Int = 0) async -> SpotifyMetadataResponse? {
        guard let songs = try? await spotifyLookupAPI.getMetadata(index: offset) else {
            return nil
        }
        return songs
    }
    
    public func isSpotifyTrackSaved(id: String) async -> Bool {
        await spotifySearchAPI.isTrackSaved(id: id)
    }
    
    public func saveSpotifyTrack(id: String) async -> Bool {
        await spotifySearchAPI.saveTrack(id: id)
    }
    
    public func deleteSpotifyTrack(id: String) async -> Bool {
        await spotifySearchAPI.deleteTrack(id: id)
    }

    public func isSpotifyAlbumSaved(id: String) async -> Bool {
        await spotifySearchAPI.isAlbumSaved(id: id)
    }

    public func saveSpotifyAlbum(id: String) async -> Bool {
        await spotifySearchAPI.saveAlbum(id: id)
    }

    public func deleteSpotifyAlbum(id: String) async -> Bool {
        await spotifySearchAPI.deleteAlbum(id: id)
    }

    
    public func searchSpotify(query: String) async -> [PlayableContent] {
        var playableContent: [PlayableContent] = []
        guard let results = await spotifySearchAPI.search(for: query, types: [.artist, .album, .playlist, .track]) else { return playableContent }

        if let tracks = results.tracks?.items {
            playableContent.append(contentsOf: tracks.compactMap(\.toPlayable))
        }
        if let tracks = results.albums?.items {
            playableContent.append(contentsOf: tracks.compactMap { $0?.toPlayable })
        }
        if let tracks = results.artists?.items {
            playableContent.append(contentsOf: tracks.map(\.toPlayable))
        }
        if let tracks = results.playlists?.items {
            playableContent.append(contentsOf: tracks.compactMap { $0?.toPlayable })
        }

        return sortContentByIntelligentSearch(playableContent: playableContent, query: query)
    }

    public func searchSpotifyPlayableContent(query: String) async -> [PlayableContent] {
        var playableContents: [PlayableContent] = []
        guard let results = await spotifySearchAPI.search(for: query, types: [.artist, .album, .playlist, .track]) else { return [] }
        if let albums = results.albums?.items.compactMap({ $0?.toPlayable }) {
            playableContents.append(contentsOf: albums)
        }

        return playableContents
    }

    public func searchAppleMusic(query: String) async -> [PlayableContent] {
        if query.count < 1 { return [] }
        guard await requestMusicAuthorization() else { return [] }
        var playableContent: [PlayableContent] = []

        async let radioResults = apple.searchRadioStations(term: query, limit: 5)

        var request = MusicCatalogSearchRequest(term: query, types: [Song.self, Album.self, Playlist.self, Artist.self])
        request.includeTopResults = false
        request.limit = 20

        if let results = try? await request.response() {
            playableContent.append(contentsOf: results.songs.map(\.toPlayable))
            playableContent.append(contentsOf: results.albums.map(\.toPlayable))
            playableContent.append(contentsOf: results.artists.map(\.toPlayable))
            playableContent.append(contentsOf: results.playlists.map { $0.toPlayable(isUserPlaylist: false) })
        }

        if let stations = try? await radioResults {
            playableContent.append(contentsOf: stations.data.compactMap(\.toPlayable))
        }

        return sortContentByIntelligentSearch(playableContent: playableContent, query: query)
    }
    
    public func searchLibraryAppleMusic(query: String) async -> [PlayableContent] {
        if query.count < 1 { return [] }
        guard await requestMusicAuthorization() else { return [] }
        let container = try? await apple.librarySearch(term: query)
        var playableContent: [PlayableContent] = []
        
        if let songs = container?.results.librarySongs {
            playableContent.append(contentsOf: songs.data.compactMap(\.toPlayable))
        }
        
        if let albums = container?.results.libraryAlbums {
            playableContent.append(contentsOf: albums.data.compactMap(\.toPlayable))
        }
        
        if let artists = container?.results.libraryArtists {
            playableContent.append(contentsOf: artists.data.compactMap(\.toPlayable))
        }
        
        if let playlists = container?.results.libraryPlaylists {
            playableContent.append(contentsOf: playlists.data.compactMap(\.toPlayable))
        }
        

        return sortContentByIntelligentSearch(playableContent: playableContent, query: query)
    }
    
    public func searchApple(query: String) async -> [PlayableContent] {
        if query.count < 1 { return [] }
        
        async let libraryResults = searchLibraryAppleMusic(query: query)
        async let appleMusicResults = searchAppleMusic(query: query)
        
        let (libResults, appleResults) = await (libraryResults, appleMusicResults)
        
        var playableContent: [PlayableContent] = []
        playableContent.append(contentsOf: libResults)
        playableContent.append(contentsOf: appleResults)

        return sortContentByIntelligentSearch(playableContent: playableContent, query: query)
    }

    public func lookup(id: String) async throws -> Song? {
        guard await requestMusicAuthorization() else { return nil }
        let musicItemID = MusicItemID(id)
        var catalogResource = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: musicItemID)
        catalogResource.properties = [.albums, .artists]
        let response = try await catalogResource.response()
        return response.items.first
    }

    public func lookup(id: String) async throws -> Album? {
        guard await requestMusicAuthorization() else { return nil }

        let albumID = MusicItemID(id)
        var catalogResource = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: albumID)
        catalogResource.properties = [.tracks, .artists, .audioVariants]
        let response = try await catalogResource.response()
        return response.items.first
    }

    /// Converts a MusicKit track collection to PlayableContent, enriching each Song
    /// with its previewAssets via a single batch catalog request.
    public func tracksToPlayableWithPreviews(_ tracks: MusicItemCollection<MusicKit.Track>) async -> [PlayableContent] {
        let songIDs = tracks.compactMap { track -> MusicItemID? in
            guard case .song(let song) = track else { return nil }
            return song.id
        }

        var previewURLs: [MusicItemID: URL] = [:]
        if !songIDs.isEmpty {
            var request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: songIDs)
            request.properties = [.previewAssets]
            if let response = try? await request.response() {
                for song in response.items {
                    if let url = song.previewAssets?.first?.url {
                        previewURLs[song.id] = url
                    }
                }
            }
        }

        return tracks.map { track in
            var playable = track.toPlayable
            if case .song(let song) = track {
                playable.previewURL = previewURLs[song.id]
            }
            return playable
        }
    }

    public func lookup(id: String) async throws -> Playlist? {
        guard await requestMusicAuthorization() else { return nil }
        let playlistID = MusicItemID(id)
        var catalogResource = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: playlistID)
        catalogResource.properties = [.tracks]
        let response = try await catalogResource.response()
        return response.items.first
    }

    public func getTracksFromPlaylist(id: String) async throws -> [MusicKit.Track] {
        let playlistID = MusicItemID(id)
        var playlistRequest = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: playlistID)
        playlistRequest.properties = [.tracks]
        
        let result = try await playlistRequest.response()
        guard let first = result.items.first else {
            throw NSError(domain: "PlaylistError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Playlist not found"])
        }
        
        let withTracks = try await first.with(.tracks)
        
        guard let startingTracks = withTracks.tracks else {
            throw NSError(domain: "PlaylistError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No tracks found in playlist"])
        }
        
        return try await getAllTracksFromPlaylist(startingTracks: startingTracks)
    }

    func getAllTracksFromPlaylist(startingTracks: MusicItemCollection<MusicKit.Track>) async throws -> [MusicKit.Track] {
        return try await withThrowingTaskGroup(of: [MusicKit.Track].self) { group in
            var allTracks: [MusicKit.Track] = []
            
            func processNextBatch(_ tracks: MusicItemCollection<MusicKit.Track>) async throws {
                group.addTask {
                    return Array(tracks)
                }
                
                if tracks.hasNextBatch {
                    if let nextBatch = try await tracks.nextBatch() {
                        try await processNextBatch(nextBatch)
                    }
                }
            }
            
            try await processNextBatch(startingTracks)
            
            for try await tracks in group {
                allTracks.append(contentsOf: tracks)
            }
            
            return allTracks
        }
    }


    public func lookup(id: String) async throws -> Artist? {
        guard await requestMusicAuthorization() else { return nil }

        let albumID = MusicItemID(id)
        var catalogResource = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: albumID)
        catalogResource.properties = [.albums, .topSongs]
        let response = try await catalogResource.response()
        return response.items.first
    }
    
    public func artistCatalog(id: String) async throws -> Artist? {
        guard await requestMusicAuthorization() else { return nil }

        let albumID = MusicItemID(id)
        var catalogResource = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: albumID)
        catalogResource.properties = [.topSongs, .albums, .appearsOnAlbums, .compilationAlbums, .liveAlbums, .fullAlbums, .latestRelease, .featuredAlbums, .playlists]
        do {
            let response = try await catalogResource.response()
            return response.items.first
        } catch {
            print(error)
        }
        
        return nil
    }
    
    public func allAlbums(id: String) async throws -> [PlayableContent] {
        guard await requestMusicAuthorization() else { return [] }
        
        let albumID = MusicItemID(id)
        var catalogResource = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: albumID)
        catalogResource.properties = [.albums, .appearsOnAlbums, .compilationAlbums, .liveAlbums, .fullAlbums, .latestRelease, .featuredAlbums]
        
        let response = try await catalogResource.response()
        guard let artist = response.items.first else { return [] }
        
        var allAlbums: [PlayableContent] = []
        
        // Combine all album types
        if let albums = artist.albums { allAlbums.append(contentsOf: albums.map(\.toPlayable)) }
        if let appearsOn = artist.appearsOnAlbums { allAlbums.append(contentsOf: appearsOn.map(\.toPlayable)) }
        if let compilations = artist.compilationAlbums { allAlbums.append(contentsOf: compilations.map(\.toPlayable)) }
        if let liveAlbums = artist.liveAlbums { allAlbums.append(contentsOf: liveAlbums.map(\.toPlayable)) }
        if let fullAlbums = artist.fullAlbums { allAlbums.append(contentsOf: fullAlbums.map(\.toPlayable)) }
        if let latest = artist.latestRelease { allAlbums.append(latest.toPlayable) }
        if let featured = artist.featuredAlbums { allAlbums.append(contentsOf: featured.map(\.toPlayable)) }
        
        // Sort by year (descending) and deduplicate
        return Array(Set(allAlbums))
            .sorted { album1, album2 in
                let year1 = album1.metadata?.albumYear ?? .now
                let year2 = album2.metadata?.albumYear ?? .now
                return year1 > year2
            }
    }

    public func appleLibraryLookup(id: String) async -> AppleLibraryContainer? {
        if let container = try? await apple.librarySongCatalog(id: id) {
            return container
        } else {
           return try? await apple.librarySong(id: id)
        }
    }

    public func appleLibraryAlbumLookup(id: String) async -> AppleLibraryContainer? {
        if let container = try? await apple.libraryAlbumFromTrack(id: id) {
            return container
        } else {
           return try? await apple.librarySong(id: id)
        }
    }
    
    public func appleLibraryAlbum(id: String) async -> AppleLibraryContainer? {
        guard let container = try? await apple.userLibraryAlbum(id: id) else { return nil }
        return container
    }
    
    public func appleLibraryPlaylist(id: String) async -> AppleLibraryContainer? {
        guard let container = try? await apple.getUserPlaylist(with: id) else { return nil }
        return container
    }
    
    public func appleLibraryArtistLookup(id: String) async -> AppleLibraryContainer? {
        let container = try? await apple.libraryArtistLookup(id: id)
        return container
    }
    
    public func appleLibraryArtistArtwork(name: String, size: Int = 100) async -> URL? {
        await apple.artistArtwork(for: name, size: size)
    }
    
    public func appleLibraryArtistAlbumLookup(id: String) async -> AppleLibraryContainer? {
        let container = try? await apple.libraryArtistAlbums(id: id)
        return container
    }

    // MARK: Tidal
    public func lookupTidalTrack(with id: String) async -> PlayableContent? {
        guard let song = await tidal.track(with: id) else { return nil }
        return song.toPlayable
    }

    public func lookupTidalAlbum(with id: String) async -> PlayableContent? {
        guard let album = await tidal.album(with: id) else { return nil }
        return album.toPlayable
    }

    public func lookupTidalAlbumTracks(id: String) async -> [PlayableContent] {
        let songs = await tidal.albumSongs(id: id)
        return songs.map { $0.toPlayable }
    }

    public func lookupTidalArtistTracks(id: String) async -> [PlayableContent] {
        let songs = await tidal.artistSongs(id: id)
        return songs.map { $0.toPlayable }
    }
    
    public func lookupTidalArtistAlbums(id: String) async -> [PlayableContent] {
        let songs = await tidal.artistAlbums(id: id)
        return songs.map { $0.toPlayable }
    }

    public func lookupTidalArtist(id: String) async -> PlayableContent? {
        guard let artist = await tidal.artist(with: id) else { return nil }
        return artist.toPlayable
    }
    
    public func lookupTidalPlaylist(id: String, cursor: String? = nil) async -> ([PlayableContent], String?) {
        guard let (songs, next) = await tidal.playlist(with: id, cursor: cursor) else { return ([], nil) }
        return (songs.compactMap(\.toPlayable), next)
    }

    private func searchTidal(query: String) async -> [PlayableContent] {
        var playableContent: [PlayableContent] = []
        guard let results = await tidal.search(for: query) else { return playableContent }
        playableContent.append(contentsOf: results.tracks.map(\.toPlayable))
        playableContent.append(contentsOf: results.albums.map(\.toPlayable))
        playableContent.append(contentsOf: results.artists.map(\.toPlayable))
        playableContent.append(contentsOf: results.playlists.map(\.toPlayable))

        return sortContentByIntelligentSearch(playableContent: playableContent, query: query)
    }

    // MARK: - PLex
    private func searchPlex(query: String) async -> [PlayableContent] {
        var playableContent: [PlayableContent] = []
        guard let results = await plex.search(for: query) else { return playableContent }
        playableContent.append(contentsOf: results.tracks.map(\.toPlayable))
        playableContent.append(contentsOf: results.album.map(\.toPlayable))
        playableContent.append(contentsOf: results.artists.map(\.toPlayable))
        playableContent.append(contentsOf: results.playlists.map(\.toPlayable))

        return sortContentByIntelligentSearch(playableContent: playableContent, query: query)
    }

    public func lookupPlexSong(with id: String) async -> PlayableContent? {
        guard let result = await plex.lookupPlexSong(key: id), let songs = result.metadata else {
            return nil
        }
        let playableContent: [PlayableContent] = songs.map(\.toPlayable)
        return playableContent.first
    }

    public func lookupPlexAlbum(id: String) async -> PlayableContent? {
        guard let key = id.removingPercentEncoding?.components(separatedBy: ":").last else { return nil }
        guard let result = await plex.lookupAlbum(key: key) else {
            return nil
        }
        return result.toPlayable
    }

    public func lookupPlexAlbumSongs(id: String) async -> [PlayableContent] {
        guard let key = id.removingPercentEncoding?.components(separatedBy: ":").last else { return [] }
        guard let result = await plex.lookupAlbumTracks(key: key), let metadata = result.metadata else {
            return []
        }
        let playableContent: [PlayableContent] = metadata.map(\.toPlayable)
        return playableContent
    }

    public func lookupPlexArtistAlbums(id: String) async -> [PlayableContent] {
        guard let key = id.removingPercentEncoding?.components(separatedBy: ":").last else { return [] }
        guard let result = await plex.lookupArtistAlbums(key: key), let metadata = result.metadata else {
            return []
        }
        let playableContent: [PlayableContent] = metadata.map(\.toPlayable)
        return playableContent
    }
    
    public func getPlexArtistAllAlbums(id: String) async -> (live: [PlayableContent], remixesAndSingles: [PlayableContent], others: [PlayableContent]) {
        guard let key = id.removingPercentEncoding?.components(separatedBy: ":").last else { return ([], [], []) }
        guard let result = await plex.getArtistAlbums(key: key) else {
            return ([], [], [])
        }

        var liveAlbums: [PlayableContent] = []
        var remixesAndSingles: [PlayableContent] = []
        var others: [PlayableContent] = []

        for section in result {
            if let identifier = section.hubIdentifier {
                if identifier.contains("live") {
                    liveAlbums.append(contentsOf: section.metadata?.map(\.toPlayable!) ?? [])
                } else if identifier.contains("singles") || identifier.contains("remix") {
                    remixesAndSingles.append(contentsOf: section.metadata?.map(\.toPlayable!) ?? [])
                } else if identifier.contains("soundtrack") || identifier.contains("compilation") || identifier.contains("demo") {
                    others.append(contentsOf: section.metadata?.map(\.toPlayable!) ?? [])
                }
            }
        }

        return (liveAlbums, remixesAndSingles, others)
    }

    public func lookupPlexTracks(id: String) async -> [PlayableContent] {
        guard let key = id.removingPercentEncoding?.components(separatedBy: ":").last else { return [] }
        return await plex.lookupArtistTopTracks(key: key, limit: 150).map(\.toPlayable)
    }

    public func lookupPlexArtist(id: String) async -> PlayableContent? {
        guard let key = id.removingPercentEncoding?.components(separatedBy: ":").last else { return nil }
        guard let result = await plex.lookupArtist(key: key) else {
            return nil
        }
        return result.toPlayable
    }

    public func lookupPlexPlaylist(id: String) async -> PlayableContent? {
        guard let key = id.removingPercentEncoding?.components(separatedBy: ":").last,
              let result = await plex.lookupPlaylist(key: key) else { return nil }
        return result.toPlayable
    }

    public func lookupPlexPlaylists(id: String, plexType: PlexMediaType = .song, ascending: Bool = true, offset: Int = 0) async -> (Int?, [PlayableContent], Duration?) {
        guard let key = id.removingPercentEncoding?.components(separatedBy: ":").last,
              let result = await plex.lookupPlaylist(key: key, type: plexType, ascending: ascending, offset: offset) else { return (nil, [], nil) }

        let playableContent: [PlayableContent] = result.metadata.map(\.toPlayable)
        var duration: Duration?
        if let totalDuration = result.duration, totalDuration > 0 {
            duration = Duration.seconds(totalDuration)
        }

        return (result.totalSize ?? result.size, playableContent, duration)
    }

    public func getPlexServers() async -> [PlexServer] {
        let plexServers = await plex.getPlexServers()
        return plexServers
    }
    
    public func getPlexLibraries() async -> [PlexLibrarySection] {
        let plexServers = await plex.getMusicLibraries()
        return plexServers
    }

    // TODO: Add remaining Info

    // MARK: - TuneIn
    private func searchTuneIn(query: String) async -> [PlayableContent] {
        let results = await tuneIn.search(for: query)
        let playableContent = results.map(\.toPlayable)
        return playableContent
    }

    public func lookupTuneInStation(id: String) async -> TuneInStation? {
        await tuneIn.lookupStation(for: id)
    }

    // TODO: Update for Media Details
    // MARK: Album/Playlist Lookup
    public func albumPlaylistLookup(from playableContent: PlayableContent) async -> (PlayableContent, [PlayableContent]) {
        switch (playableContent.content.type, playableContent.content.service) {
        case (.album, .apple):
            guard let album: Album = try? await lookup(id: playableContent.content.id),
                  let tracks = album.tracks else {
                    return (playableContent, [])
            }
            return (album.toPlayable, tracks.map(\.toPlayable))

//        case (.album, .spotify):
//            guard let albumDetails = await spotifyAlbumTracksLookup(id: playableContent.content.id) else { return }
//            self.tracks = albumDetails.tracks.items.map { $0.toPlayable(artwork: albumDetails.images.thumbnail) }
//        case (.playlist, .apple):
//            guard let playlist: Playlist = try? await lookup(id: playableContent.content.id) else { return }
//            artworkURL = playlist.artwork?.url(width: 600, height: 600)
//            guard let tracks = playlist.tracks else { return }
//            self.tracks = tracks.map(\.toPlayable)
//        case (.userPlaylist, .apple):
//            self.tracks = await tracksForUserPlaylists(id: playableContent.id)
//        case (.playlist, .spotify):
//            guard let playlist: SpotifyPlaylistItems = await spotifyPlaylistLookup(id: playableContent.content.id) else { return }
//            guard let items = playlist.tracks.items else { return }
//            self.tracks = items.map { $0.track.toPlayable(artwork: $0.track.album?.images.thumbnail)}
//        case (.track, .apple):
//            guard let song: Song = try? await MusicSearchService().lookup(id: playableContent.content.id), let albumID = song.albums?.first?.id.description else { return }
//            guard let album: Album = try? await MusicSearchService().lookup(id: albumID) else { return }
//            artworkURL = album.artwork?.url(width: 600, height: 600)
//            playableContent = album.toPlayable
//            guard let tracks = album.tracks else { return }
//            self.tracks = tracks.map(\.toPlayable)
//        case (.track, .spotify):
//            guard let song = await MusicSearchService().spotifyTrackLookup(id: playableContent.content.id) else { return }
//            guard let albumDetails = await MusicSearchService().spotifyAlbumTracksLookup(id: song.album.id) else { return }
//            playableContent = albumDetails.toPlayable
//            artworkURL = albumDetails.images.biggestImageURL
//            self.tracks = albumDetails.tracks.items.map { $0.toPlayable(artwork: albumDetails.images.thumbnail) }
//        case (.album, .library):
//            artworkURL = playableContent.artwork
//            self.tracks = await sonosService.libraryLookup(ID: playableContent.id)
//        case (.playlist, .library):
//            artworkURL = playableContent.artwork
//            self.tracks = await sonosService.sonosPlaylistsTracks(for: playableContent.id)
//        case (.track, .library):
//            artworkURL = playableContent.artwork
//            guard let albumName = playableContent.metadata?.album,
//                  let albumNameEncoded = albumName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
//
//            self.tracks = await sonosService.libraryAlbum(name: albumName)
//            guard let albumPlayable =  await sonosService.libraryLookup(ID: "A:ALBUM:\(albumNameEncoded)").first else { return }
//            playableContent = albumPlayable
//        case (.album, .tidal):
//            self.tracks = await MusicSearchService().lookupTidalAlbumTracks(id: playableContent.content.id)
//        case (.track, .tidal):
//            if let albumID = playableContent.metadata?.albumID {
//                guard let album = await MusicSearchService().lookupTidalAlbum(with: albumID) else { return }
//                self.tracks = await MusicSearchService().lookupTidalAlbumTracks(id: albumID)
//                playableContent = album
//            } else {
//                guard let albumID = await MusicSearchService().lookupTidalTrack(with: playableContent.id)?.metadata?.albumID else { return }
//                guard let album = await MusicSearchService().lookupTidalAlbum(with: albumID) else { return }
//                self.tracks = await MusicSearchService().lookupTidalAlbumTracks(id: albumID)
//                playableContent = album
//            }
//        case (.album, .plex):
//            self.tracks = await MusicSearchService().lookupPlexAlbumSongs(id: playableContent.content.id)
//        case (.playlist, .plex):
//            self.tracks = await MusicSearchService().lookupPlexPlaylists(id: playableContent.content.id)
        default:
            return (playableContent, [])
        }
    }

    func sortContentByIntelligentSearch(playableContent: [PlayableContent], query: String) -> [PlayableContent] {
        let lowerQuery = query.lowercased()
        
        // Create a dictionary to store unique items and their scores
        var uniqueItems: [String: (PlayableContent, Double)] = [:]
        
        // Calculate scores and store unique items
        for item in playableContent {
            let score = intelligentSearchScore(item: item, query: lowerQuery)
            let key = "\(item.id)-\(item.title)-\(item.subtitle)" // Create a unique key
            
            if let existingItem = uniqueItems[key] {
                // If item already exists, keep the one with the higher score
                if score > existingItem.1 {
                    uniqueItems[key] = (item, score)
                }
            } else {
                uniqueItems[key] = (item, score)
            }
        }
        
        // Sort the unique items
        let sortedItems = uniqueItems.values.sorted { (item1, item2) in
            let (content1, score1) = item1
            let (content2, score2) = item2
            
            // Primary sort by intelligent search score (descending)
            if score1 != score2 {
                return score1 > score2
            }
            
            // Secondary sort by title (alphabetically)
            return content1.title.localizedCaseInsensitiveCompare(content2.title) == .orderedAscending
        }
        
        // Return the sorted and deduplicated content
        return sortedItems.map { $0.0 }
    }
    
    func intelligentSearchScore(item: PlayableContent, query: String) -> Double {
        let titleScore = fuzzyMatchScore(source: item.title, query: query)
        let subtitleScore = fuzzyMatchScore(source: item.subtitle, query: query)
        let popularityScore = Double(item.metadata?.popularity ?? 0)

        // Normalize scores
        let maxTitleScore = Double(query.count) // Maximum possible title score
        let maxSubtitleScore = Double(query.count) // Maximum possible subtitle score
        let maxPopularity: Double = 100 // Adjust based on your popularity scale

        let normalizedTitleScore = Double(titleScore) / maxTitleScore
        let normalizedSubtitleScore = Double(subtitleScore) / maxSubtitleScore
        let normalizedPopularity = min(popularityScore / maxPopularity, 1.0)

        // Boost for catalog content over library content (especially artists)
        let catalogBoost: Double
        switch item.content.type {
        case .artist:
            catalogBoost = 0.3 // Strong boost for catalog artists
        case .album, .track:
            catalogBoost = 0.1 // Smaller boost for catalog albums/tracks
        case .libraryArtist:
            catalogBoost = -0.1 // Slight penalty for library artists
        default:
            catalogBoost = 0.0
        }

        // Weighting factors
        let titleWeight = 0.3
        let subtitleWeight = 0.10
        let popularityWeight = 0.5

        // Calculate weighted score
        let weightedScore =
            normalizedTitleScore * titleWeight +
            normalizedSubtitleScore * subtitleWeight +
            normalizedPopularity * popularityWeight +
            catalogBoost

        return weightedScore
    }

    func fuzzyMatchScore(source: String, query: String) -> Int {
        let lowerSource = source.lowercased()
        var score = 0
        var sourceIndex = lowerSource.startIndex
        
        for queryChar in query {
            if let foundIndex = lowerSource[sourceIndex...].firstIndex(of: queryChar) {
                score += 1
                sourceIndex = lowerSource.index(after: foundIndex)
            }
        }
        
        return score
    }
    
    public func requestMusicAuthorization() async -> Bool {
        let status = await MusicAuthorization.request()

        switch status {
        case .notDetermined:
            appleMusicAuthorizationStatus = .notDetermined
        case .denied, .restricted:
            appleMusicAuthorizationStatus = .denied
        case .authorized:
            appleMusicAuthorizationStatus = .authorized
            return true
        default:
            appleMusicAuthorizationStatus = .denied
        }
        return false
    }

    public func getMusicAuthorization() -> AppleMusicAuthorization {
        let status = MusicAuthorization.currentStatus

        switch status {
        case .notDetermined:
            appleMusicAuthorizationStatus = .notDetermined
        case .denied, .restricted:
            appleMusicAuthorizationStatus = .denied
        case .authorized:
            appleMusicAuthorizationStatus = .authorized
        default:
            appleMusicAuthorizationStatus = .denied
        }
        return appleMusicAuthorizationStatus
    }

    // Add SoundCloud search method
    private func searchSoundCloud(query: String) async -> [PlayableContent] {
        var playableContent: [PlayableContent] = []
        
        async let tracks = soundCloud.searchTracks(for: query)
        async let playlists = soundCloud.searchPlaylists(for: query)
        
        guard let trackResults = await tracks,
              let playlistResults = await playlists else { return playableContent }
        
        playableContent.append(contentsOf: trackResults.tracks.map { track in
            createSoundCloudPlayableContent(from: track)
        })
        
        playableContent.append(contentsOf: playlistResults.tracks.map { track in
            PlayableContent(
                title: track.title,
                subtitle: track.description ?? "",
                thumbnail: URL(string: track.artworkUrl ?? ""),
                artwork: track.artworkURLOriginal,
                content: MediaContent(
                    service: .soundcloud,
                    id: String(track.id),
                    type: .playlist,
                    location: URL(string: track.permalinkUrl ?? "")
                ),
                metadata: .init(
                    artist: nil,
                    album: nil
                )
            )
        })
        
        return sortContentByIntelligentSearch(playableContent: playableContent, query: query)
    }
    
    // SoundCloud track lookup
    public func lookupSoundCloudTrack(with id: String) async -> PlayableContent? {
        guard let track = await soundCloud.track(for: id) else { return nil }
        return createSoundCloudPlayableContent(from: track)
    }
    
    // SoundCloud track lookup
    public func lookupSoundCloudPlaylistTracks(with id: String, nextCursor: String?) async -> (tracks: [PlayableContent], nextCursor: String?) {
        guard let response = await soundCloud.playlistTracks(for: id, cursor: nextCursor) else { return ([], nil) }
        return (response.collection.map { createSoundCloudPlayableContent(from: $0) }, response.nextCursor)
    }
    
    // SoundCloud liked tracks
    public func getSoundCloudLikedTracks(cursor: String? = nil) async -> (tracks: [PlayableContent], nextCursor: String?) {
        guard let response = await soundCloud.getLikedTracks(cursor: cursor) else { 
            return (tracks: [], nextCursor: nil) 
        }
        
        let tracks = response.collection.map { createSoundCloudPlayableContent(from: $0) }
        return (tracks: tracks, nextCursor: response.nextCursor)
    }
    
    public func likeSoundCloudTrack(id: String) async -> Bool {
        return await soundCloud.likeTrack(trackId: id)
    }
    
    public func unlikeSoundCloudTrack(id: String) async -> Bool {
        return await soundCloud.unlikeTrack(trackId: id)
    }
    
    public func isSoundCloudTrackLiked(id: String) async -> Bool? {
        let (tracks, _) = await getSoundCloudLikedTracks()
        return tracks.contains { $0.content.id == id }
    }

    public func ratePlexTrack(trackID: String, rating: Int) async -> Bool {
        guard let ratingKey = plexRatingKey(from: trackID) else { return false }
        return await PlexAPI.shared.rateTrack(ratingKey: ratingKey, rating: rating)
    }

    public func getPlexTrackRating(trackID: String) async -> Double? {
        guard let ratingKey = plexRatingKey(from: trackID) else { return nil }
        return await PlexAPI.shared.getTrackRating(ratingKey: ratingKey)
    }

    private func plexRatingKey(from trackID: String) -> String? {
        let decoded = trackID.removingPercentEncoding ?? trackID
        // Format: clientID:3:ratingKey
        guard let separatorRange = decoded.range(of: ":3:") else { return nil }
        return String(decoded[separatorRange.upperBound...])
    }
    
    public func getSoundCloudLikedPlaylists(cursor: String? = nil) async -> (playlists: [PlayableContent], nextCursor: String?) {
        guard let response = await soundCloud.getLikedPlaylists(cursor: cursor) else { 
            return (playlists: [], nextCursor: nil) 
        }
        
        let playlists = response.collection.map { createSoundCloudPlayableContentFromPlaylist(from: $0) }
        return (playlists: playlists, nextCursor: response.nextCursor)
    }
    
    // Helper method to create PlayableContent from SoundCloudPlaylist
    private func createSoundCloudPlayableContentFromPlaylist(from playlist: SoundCloudPlaylist) -> PlayableContent {
        let artist = playlist.user?.username ?? ""
        let subtitle = artist.isEmpty ? (playlist.description ?? "") : artist
        
        return PlayableContent(
            title: playlist.title,
            subtitle: subtitle,
            thumbnail: URL(string: playlist.artworkUrl ?? ""),
            artwork: playlist.artworkURLOriginal,
            content: MediaContent(
                service: .soundcloud,
                id: String(playlist.id),
                type: .playlist,
                location: URL(string: playlist.permalinkUrl ?? "")
            )
        )
    }
    
    // Helper method to create PlayableContent from SoundCloudTrack
    private func createSoundCloudPlayableContent(from track: SoundCloudTrack) -> PlayableContent {
        let artist = track.metadataArtist ?? track.user?.username ?? ""
        let subtitle = artist.isEmpty ? (track.description ?? "") : artist

        return PlayableContent(
            title: track.title,
            subtitle: subtitle,
            thumbnail: URL(string: track.artworkUrl ?? ""),
            artwork: track.artworkURLOriginal,
            content: MediaContent(
                service: .soundcloud,
                id: String(track.id),
                type: .track,
                location: URL(string: track.permalinkUrl ?? "")
            ),
            metadata: .init(
                artist: artist.isEmpty ? nil : artist,
                album: nil,
                fingerprint: String(track.id)
            )
        )
    }

    private func searchDeezer(query: String) async -> [PlayableContent] {
        async let tracks = deezer.search(for: query)
        async let albums = deezer.searchAlbums(for: query)
        async let artists = deezer.searchArtists(for: query)
        async let playlists = deezer.searchPlaylists(for: query)

        var content: [PlayableContent] = []
        content.append(contentsOf: await tracks.map { createDeezerPlayableContent(from: $0) })
        content.append(contentsOf: await albums.map { createDeezerAlbumContent(from: $0) })
        content.append(contentsOf: await artists.map { createDeezerArtistContent(from: $0) })
        content.append(contentsOf: await playlists.map { createDeezerPlaylistContent(from: $0) })
        return sortContentByIntelligentSearch(playableContent: content, query: query)
    }

    public func lookupDeezerTrack(with id: String) async -> PlayableContent? {
        guard let track = await deezer.track(for: id) else { return nil }
        return createDeezerPlayableContent(from: track)
    }

    public func lookupDeezerAlbum(with id: String) async -> PlayableContent? {
        guard let album = await deezer.album(for: id) else { return nil }
        return createDeezerAlbumContent(from: album)
    }

    public func lookupDeezerAlbumTracks(id: String) async -> [PlayableContent] {
        await deezer.albumTracks(for: id).map { createDeezerPlayableContent(from: $0) }
    }

    public func lookupDeezerArtistTopTracks(id: String) async -> [PlayableContent] {
        await deezer.artistTopTracks(for: id).map { createDeezerPlayableContent(from: $0) }
    }

    public func lookupDeezerArtistAlbums(id: String) async -> [PlayableContent] {
        await deezer.artistAlbums(for: id).map { createDeezerAlbumContent(from: $0) }
    }

    public func lookupDeezerArtist(id: String) async -> PlayableContent? {
        guard let artist = await deezer.artist(for: id) else { return nil }
        return createDeezerArtistContent(from: artist)
    }

    public func lookupDeezerPlaylist(with id: String) async -> PlayableContent? {
        guard let playlist = await deezer.playlist(for: id) else { return nil }
        return createDeezerPlaylistContent(from: playlist)
    }

    public func lookupDeezerPlaylistTracks(id: String) async -> [PlayableContent] {
        await deezer.playlistTracks(for: id).map { createDeezerPlayableContent(from: $0) }
    }

    // MARK: - Deezer user library

    private func deezerToken() async -> String? {
        try? await KeychainTokenRefreshHandler.shared.getAccessToken(for: .deezer)
    }

    public func deezerUserFavoriteTracks(offset: Int = 0) async -> [PlayableContent] {
        guard let token = await deezerToken() else { return [] }
        return await deezer.userFavoriteTracks(accessToken: token, index: offset).map { createDeezerPlayableContent(from: $0) }
    }

    public func deezerUserFavoriteAlbums(offset: Int = 0) async -> [PlayableContent] {
        guard let token = await deezerToken() else { return [] }
        return await deezer.userFavoriteAlbums(accessToken: token, index: offset).map { createDeezerAlbumContent(from: $0) }
    }

    public func deezerUserFavoriteArtists(offset: Int = 0) async -> [PlayableContent] {
        guard let token = await deezerToken() else { return [] }
        return await deezer.userFavoriteArtists(accessToken: token, index: offset).map { createDeezerArtistContent(from: $0) }
    }

    public func deezerUserPlaylists(offset: Int = 0) async -> [PlayableContent] {
        guard let token = await deezerToken() else { return [] }
        return await deezer.userPlaylists(accessToken: token, index: offset).map { createDeezerPlaylistContent(from: $0) }
    }

    public func deezerUserHistory() async -> [PlayableContent] {
        guard let token = await deezerToken() else { return [] }
        return await deezer.userHistory(accessToken: token).map { createDeezerPlayableContent(from: $0) }
    }

    public var isDeezerAuthenticated: Bool {
        get async { await deezerToken() != nil }
    }

    public func likeDeezerTrack(id: String) async -> Bool {
        guard let creds = await deezerSMAPICredentials() else { return false }
        return await deezer.rateItem(credentials: creds, smapiID: "tr-flac:\(id)", rating: 1)
    }

    public func unlikeDeezerTrack(id: String) async -> Bool {
        guard let creds = await deezerSMAPICredentials() else { return false }
        return await deezer.rateItem(credentials: creds, smapiID: "tr-flac:\(id)", rating: 0)
    }

    public func isDeezerTrackLiked(id: String) async -> Bool {
        guard let creds = await deezerSMAPICredentials() else { return false }
        return await deezer.isItemLiked(credentials: creds, smapiID: "tr-flac:\(id)")
    }

    private func deezerSMAPICredentials() async -> SMAPICredentials? {
        guard let creds = try? await KeychainTokenRefreshHandler.shared.getCredentials(for: .deezer) else { return nil }
        return SMAPICredentials(token: creds.token, key: creds.key, householdId: creds.householdId)
    }


    private func createDeezerPlayableContent(from track: DeezerTrack) -> PlayableContent {
        let artist = track.artist?.name ?? ""
        let subtitle = artist.isEmpty ? (track.album?.title ?? "") : artist

        return PlayableContent(
            title: track.title,
            subtitle: subtitle,
            thumbnail: track.album?.artworkURL,
            artwork: track.album?.artworkURL,
            content: MediaContent(
                service: .deezer,
                id: String(track.id),
                type: .track,
                location: URL(string: "https://www.deezer.com/track/\(track.id)")
            ),
            previewURL: track.previewURL,
            metadata: .init(
                artist: artist.isEmpty ? nil : artist,
                artistID: track.artist.map { String($0.id) },
                album: track.album?.title,
                albumID: track.album.map { String($0.id) },
                fingerprint: String(track.id)
            )
        )
    }

    private func createDeezerAlbumContent(from album: DeezerAlbum) -> PlayableContent {
        let artistName = album.artist?.name ?? ""
        let subtitle = [artistName.isEmpty ? nil : artistName, album.releaseYear].compactMap { $0 }.joined(separator: " • ")
        return PlayableContent(
            title: album.title,
            subtitle: subtitle,
            thumbnail: album.artworkURL,
            artwork: album.artworkURL,
            content: MediaContent(
                service: .deezer,
                id: String(album.id),
                type: .album,
                location: URL(string: "https://www.deezer.com/album/\(album.id)")
            ),
            metadata: .init(
                artist: artistName.isEmpty ? nil : artistName,
                artistID: album.artist.map { String($0.id) }
            )
        )
    }

    private func createDeezerArtistContent(from artist: DeezerArtist) -> PlayableContent {
        PlayableContent(
            title: artist.name,
            subtitle: "",
            thumbnail: artist.artworkURL,
            artwork: artist.artworkURL,
            content: MediaContent(
                service: .deezer,
                id: String(artist.id),
                type: .artist,
                location: URL(string: "https://www.deezer.com/artist/\(artist.id)")
            )
        )
    }

    private func createDeezerPlaylistContent(from playlist: DeezerPlaylist) -> PlayableContent {
        PlayableContent(
            title: playlist.title,
            subtitle: playlist.user?.name ?? "",
            thumbnail: playlist.artworkURL,
            artwork: playlist.artworkURL,
            content: MediaContent(
                service: .deezer,
                id: String(playlist.id),
                type: .playlist,
                location: URL(string: "https://www.deezer.com/playlist/\(playlist.id)")
            )
        )
    }
}
