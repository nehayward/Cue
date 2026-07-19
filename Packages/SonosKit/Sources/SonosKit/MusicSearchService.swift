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
    /// Session cache of the user's editable playlist ids per service, so the "can edit this
    /// playlist?" check is instant after the first fetch (also warmed by the add-to-playlist sheet).
    @ObservationIgnored private var editablePlaylistIDsCache: [MusicService: Set<String>] = [:]
    /// Cached Spotify user id (fetched once) for the fast owner-based editability check.
    @ObservationIgnored private var spotifyUserID: String?
    /// Cached Deezer user id (fetched once) for the owner-based editability check.
    @ObservationIgnored private var deezerUserID: Int?
    private let spotifyLookupAPI = SpotifySonosAPI(tokenRefreshHandler: KeychainTokenRefreshHandler.shared)
    private let tuneIn = TuneInAPI()
    private let sonosService = SonosService.shared

    private let soundCloud = SoundCloudAPI(
        clientId: "iJ161hwUtTqVKptbddkz1NWBYpQDDIcl",
        clientSecret: "zCcBaeVvBKX4R0eAwypLes8PmBknZnqI",
        tokenRefreshHandler: KeychainTokenRefreshHandler.shared
    )
    private let deezer = DeezerAPI()
    private let sonosRadio = SonosRadioAPI()
    /// Sonos Radio's service-registry id, used to resolve its SMAPI endpoint and
    /// to classify its account. Distinct from the playback sid (303).
    private static let sonosRadioServiceID = "77575"
    /// Cached resolved SMAPI endpoint for Sonos Radio.
    private var cachedSonosRadioEndpoint: URL?

    private var searchSuggestionTask = Task<([MusicCatalogSearchSuggestionsResponse.Suggestion], MusicItemCollection<MusicCatalogSearchSuggestionsResponse.TopResult>)?, Never> { nil }

    private let debounceDuration: Duration = .milliseconds(150)

    public var suggestions: [MusicCatalogSearchSuggestionsResponse.Suggestion] = []

    public var results: [PlayableContent] = []
    public var newReleases: [SpotifyAlbumItem] = []

    /// IDs of recently played items for the CURRENT search, captured from the
    /// `search(for:recentlyPlayedIDs:)` parameter — private plumbing so the
    /// per-provider ranking helpers can read them; the public contract is the
    /// parameter, not ambient state.
    @ObservationIgnored private var recentlyPlayedIDs: Set<String> = []

    public init() {}

    /// Returns whether every provider answered. `false` means at least one
    /// provider timed out or failed and the published results are partial —
    /// callers memoizing "this query is done" (the search screen's
    /// skip-identical-re-search guard) must not cache a partial answer.
    ///
    /// - Parameter recentlyPlayedIDs: optional IDs of items the user has
    ///   played (e.g. from the app's play history) so ranking can boost them;
    ///   omitted, ranking simply applies no boost.
    @discardableResult
    public func search(for providers: Set<MediaSearchService>, recentlyPlayedIDs: Set<String> = []) async -> Bool {
        self.recentlyPlayedIDs = recentlyPlayedIDs
        if query.isEmpty {
            results = []
            return true
        }

        var allProvidersAnswered = true
        let capturedQuery = query
        searchSuggestionTask.cancel()
        searchSuggestionTask = Task { [weak self] in
            guard let self else { return nil }
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return nil }
            let results = await searchSuggestion(query: capturedQuery)
            return results
        }

        // With several providers selected, results accumulate into one
        // merged, deduplicated, re-ranked list instead of last-writer-wins.
        let isMultiServiceSearch = providers.count > 1
        // Keyed by provider (not appended in arrival order) so the merged input
        // is rebuilt in a stable service order every time a provider drains.
        // Network timing decides which provider returns first; feeding the
        // ranking in that order made the tie-break — which preserves input
        // order for equally-scoring items — reshuffle the artist's many
        // same-ranked albums on each republish, so the list appeared to
        // rebuild itself as results came in or when the view re-rendered.
        var resultsByProvider: [MediaSearchService: [PlayableContent]] = [:]

        await withTaskGroup(of: (MediaSearchService, [PlayableContent]?).self) { group in
            for provider in providers {
                group.addTask { [weak self] in
                    guard let self else { return (provider, nil) }
                    try? await Task.sleep(for: self.debounceDuration)
                    guard !Task.isCancelled else { return (provider, nil) }

                    // Each provider races a deadline: an unreachable service
                    // (the Sonos library or a LAN Plex server while away from
                    // that network) would otherwise sit in connect/timeout for
                    // up to 15s — and since a merged search publishes once,
                    // one dead provider held up every other service's results.
                    // A timed-out provider just contributes nothing.
                    let fetched = await Self.withTimeout(seconds: Self.providerTimeout) {
                        switch provider {
                        case .apple:
                            await self.searchApple(query: capturedQuery)
                        case .spotify:
                            await self.searchSpotify(query: capturedQuery)
                        case .library:
                            await self.sortContentByIntelligentSearch(
                                playableContent: self.sonosService.librarySearch(query: capturedQuery),
                                query: capturedQuery
                            )
                        case .plex:
                            await self.searchPlex(query: capturedQuery)
                        case .tidal:
                            await self.searchTidal(query: capturedQuery)
                        case .tuneIn:
                            await self.searchTuneIn(query: capturedQuery)
                        case .soundcloud:
                            await self.searchSoundCloud(query: capturedQuery)
                        case .deezer:
                            await self.searchDeezer(query: capturedQuery)
                        case .sonosRadio:
                            await self.searchSonosRadio(query: capturedQuery)
                        }
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
                guard let providerResults else {
                    // Not cancelled and still the current query: the provider
                    // timed out or failed. A single-service search must clear
                    // — leaving `results` untouched presented the PREVIOUS
                    // query's list as this query's answer.
                    allProvidersAnswered = false
                    if !isMultiServiceSearch {
                        self.results = []
                    }
                    continue
                }
                if provider == .tuneIn || provider == .sonosRadio, !isMultiServiceSearch {
                    self.suggestions.removeAll()
                }
                if isMultiServiceSearch {
                    resultsByProvider[provider] = providerResults
                } else {
                    self.results = providerResults
                }
            }
        }

        if Task.isCancelled { return false }
        if self.query != capturedQuery { return false }

        if isMultiServiceSearch {
            // Publish the merged list once, after every provider has drained.
            // Publishing per-arrival re-ranked the visible list on each
            // provider's completion: a slower service's copy of the artist
            // joined the grouped cluster at the top and shoved everything
            // below it down a row seconds after results appeared. Providers
            // run concurrently, so this waits only for the slowest one.
            //
            // Merged in a fixed service order (the enum's case order), not
            // completion order, so the ranking receives the same input
            // sequence every time. groupArtists clusters each artist's
            // per-service copies at the top.
            let mergedResults = MediaSearchService.allCases
                .compactMap { resultsByProvider[$0] }
                .flatMap { $0 }
            self.results = SearchRanking.sort(
                mergedResults,
                query: capturedQuery,
                recentlyPlayedIDs: recentlyPlayedIDs,
                groupArtists: true
            )
        }

        if let suggestionResults = await searchSuggestionTask.value {
            if !providers.contains(.tuneIn) && !providers.contains(.sonosRadio) {
                suggestions = suggestionResults.0
            }
        }

        return allProvidersAnswered
    }

    /// Deadline for a single provider's fetch. Generous for a healthy
    /// service (all respond within a couple of seconds) while keeping an
    /// unreachable one from pinning the merged publish to the network
    /// stack's 15s connect timeout.
    private static let providerTimeout: TimeInterval = 8

    /// Races `operation` against a deadline; returns nil when the deadline
    /// wins (the losing fetch is cancelled, and URLSession-backed calls
    /// honor that).
    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let winner = await group.next() ?? nil
            group.cancelAll()
            return winner
        }
    }

    // Convenience methods for single provider and array of providers
    public func search(for provider: MediaSearchService, recentlyPlayedIDs: Set<String> = []) async {
        await search(for: [provider], recentlyPlayedIDs: recentlyPlayedIDs)
    }

    public func search(for providers: [MediaSearchService], recentlyPlayedIDs: Set<String> = []) async {
        await search(for: Set(providers), recentlyPlayedIDs: recentlyPlayedIDs)
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

    // MARK: - Playlist Management

    /// The user's editable Apple Music library playlists, as `PlayableContent`.
    public func appleUserPlaylists() async -> [PlayableContent] {
        guard let container = try? await apple.getUserPlaylists(limit: 100) else { return [] }
        return container.data.compactMap { item in
            guard let name = item.attributes.name else { return nil }
            return PlayableContent(
                title: name,
                subtitle: "",
                thumbnail: item.attributes.artwork?.urlWithSize(width: 100, height: 100),
                artwork: item.attributes.artwork?.urlWithSize(width: 600, height: 600),
                content: MediaContent(service: .apple, id: item.id, type: .libraryPlaylist, location: nil),
                metadata: .init()
            )
        }
    }

    /// Creates a new Apple Music library playlist, optionally seeded with `track`.
    public func createApplePlaylist(name: String, addingTrack track: PlayableContent? = nil) async -> PlayableContent? {
        guard let id = try? await apple.createLibraryPlaylist(name: name) else { return nil }
        if let track { _ = await addToApplePlaylist(track: track, playlistID: id) }
        return PlayableContent(
            title: name,
            subtitle: "",
            thumbnail: nil,
            artwork: nil,
            content: MediaContent(service: .apple, id: id, type: .libraryPlaylist, location: nil),
            metadata: .init()
        )
    }

    /// Adds a track to an Apple Music library playlist.
    public func addToApplePlaylist(track: PlayableContent, playlistID: String) async -> Bool {
        let type = track.content.type == .libraryTrack ? "library-songs" : "songs"
        return (try? await apple.addSongToPlaylist(songId: track.content.id, type: type, playlistID: playlistID)) ?? false
    }

    /// The user's editable Spotify playlists (owned or collaborative), as `PlayableContent`.
    public func spotifyEditablePlaylists() async -> [PlayableContent] {
        let playlists = await spotifySearchAPI.editableUserPlaylists().compactMap(\.toPlayable)
        editablePlaylistIDsCache[.spotify] = Set(playlists.map(\.id))
        return playlists
    }

    /// Creates a new Spotify playlist, optionally seeded with `track`.
    public func createSpotifyPlaylist(name: String, addingTrack track: PlayableContent? = nil) async -> PlayableContent? {
        guard let id = await spotifySearchAPI.createPlaylist(name: name) else { return nil }
        if let track { _ = await addToSpotifyPlaylist(track: track, playlistID: id) }
        editablePlaylistIDsCache[.spotify, default: []].insert(id)
        return PlayableContent(
            title: name,
            subtitle: "",
            thumbnail: nil,
            artwork: nil,
            content: MediaContent(service: .spotify, id: id, type: .playlist, location: URL(string: "https://open.spotify.com/playlist/\(id)")),
            metadata: nil
        )
    }

    /// Adds a track — or, for an album, all of its tracks — to a Spotify playlist.
    public func addToSpotifyPlaylist(track: PlayableContent, playlistID: String) async -> Bool {
        let uris: [String]
        if [.album, .libraryAlbum].contains(track.content.type) {
            uris = await spotifyAlbumTrackURIs(albumID: track.content.id)
        } else {
            uris = ["spotify:track:\(track.content.id)"]
        }
        guard !uris.isEmpty else { return false }
        // Spotify's add-tracks endpoint accepts at most 100 URIs per request, so a long album is
        // posted in chunks — otherwise the request is rejected and nothing is added.
        for start in stride(from: 0, to: uris.count, by: 100) {
            let chunk = Array(uris[start..<min(start + 100, uris.count)])
            guard await spotifySearchAPI.addTracksToPlaylist(playlistID: playlistID, trackURIs: chunk) else { return false }
        }
        return true
    }

    /// Every track URI for a Spotify album, paging through the album's embedded track list.
    /// `/v1/albums/{id}` returns at most 50 tracks per page, so a large album (box set/compilation)
    /// has to be walked by offset — otherwise tracks past the first page are silently dropped.
    private func spotifyAlbumTrackURIs(albumID: String) async -> [String] {
        let pageLimit = 50
        var uris: [String] = []
        var offset = 0
        while true {
            guard let details = await spotifyAlbumTracksLookup(id: albumID, offset: offset, limit: pageLimit) else { break }
            let page = details.tracks.items
            uris.append(contentsOf: page.map(\.uri))
            offset += page.count
            if page.count < pageLimit { break }
            if let total = details.tracks.total, offset >= total { break }
        }
        return uris
    }

    /// Removes a track from a Spotify playlist. When `position` is the track's playlist index, only
    /// that occurrence is removed; otherwise Spotify removes every occurrence of the track.
    public func removeFromSpotifyPlaylist(track: PlayableContent, playlistID: String, position: Int? = nil) async -> Bool {
        let positions = position.map { [$0] }
        return await spotifySearchAPI.removeTracksFromPlaylist(playlistID: playlistID, trackURIs: ["spotify:track:\(track.content.id)"], positions: positions)
    }

    /// Removes a Spotify playlist from the user's library (unfollow).
    public func deleteSpotifyPlaylist(playlistID: String) async -> Bool {
        let success = await spotifySearchAPI.unfollowPlaylist(playlistID: playlistID)
        if success { editablePlaylistIDsCache[.spotify]?.remove(playlistID) }
        return success
    }

    // MARK: Plex

    /// The user's Plex audio playlists, as `PlayableContent`.
    public func plexUserPlaylists() async -> [PlayableContent] {
        await plex.playlists().map(\.toPlayable)
    }

    /// Creates a new Plex playlist, optionally seeded with `track`, returned as `PlayableContent`.
    /// Creates a Plex playlist, optionally seeded with `track` (omit it for an empty playlist).
    public func createPlexPlaylist(name: String, track: PlayableContent? = nil) async -> PlayableContent? {
        // Seeded create — Plex builds the playlist directly from the track.
        if let trackKey = track.flatMap({ plexRatingKey(from: $0.content.id) }) {
            guard let newKey = await plex.createPlaylist(title: name, trackRatingKey: trackKey) else { return nil }
            return await plex.lookupPlaylist(key: newKey)?.toPlayable
        }
        // Empty playlist — Plex rejects an item-less create (400 Bad Request), so seed it with any
        // library track and then remove that track, leaving the playlist empty.
        guard let seedKey = await plex.songs(offset: 0, limit: 1).first?.ratingKey,
              let newKey = await plex.createPlaylist(title: name, trackRatingKey: seedKey) else { return nil }
        if let items = await plex.lookupPlaylist(key: newKey, type: .song, ascending: true)?.metadata {
            for itemID in items.compactMap(\.playlistItemID) {
                _ = await plex.removeFromPlaylist(playlistRatingKey: newKey, playlistItemID: "\(itemID)")
            }
        }
        return await plex.lookupPlaylist(key: newKey)?.toPlayable
    }

    /// Adds a track to a Plex playlist.
    public func addToPlexPlaylist(track: PlayableContent, playlistID: String) async -> Bool {
        guard let trackKey = plexRatingKey(from: track.content.id),
              let playlistKey = plexRatingKey(from: playlistID) else { return false }
        return await plex.addToPlaylist(playlistRatingKey: playlistKey, trackRatingKey: trackKey)
    }

    /// Removes a track from a Plex playlist. Requires the track's `playlistItemID` (populated when
    /// the track was loaded from a playlist).
    public func removeFromPlexPlaylist(track: PlayableContent, playlistID: String) async -> Bool {
        guard let playlistItemID = track.metadata?.playlistItemID,
              let playlistKey = plexRatingKey(from: playlistID) else { return false }
        return await plex.removeFromPlaylist(playlistRatingKey: playlistKey, playlistItemID: playlistItemID)
    }

    /// Deletes a Plex playlist.
    public func deletePlexPlaylist(playlistID: String) async -> Bool {
        guard let playlistKey = plexRatingKey(from: playlistID) else { return false }
        return await plex.deletePlaylist(ratingKey: playlistKey)
    }

    // MARK: Deezer

    /// Creates a new Deezer playlist, optionally seeded with `track`.
    /// Requires a Deezer token with the `manage_library` scope.
    public func createDeezerPlaylist(name: String, track: PlayableContent? = nil) async -> PlayableContent? {
        guard let token = await deezerToken(),
              let newID = await deezer.createPlaylist(title: name, accessToken: token) else { return nil }
        if let track { _ = await deezer.addTracks(playlistID: newID, trackIDs: [track.content.id], accessToken: token) }
        // Prefer a refetch so the content carries artwork and counts; fall back to a minimal
        // representation if the new playlist isn't queryable yet.
        if let refetched = await lookupDeezerPlaylist(with: newID) { return refetched }
        return PlayableContent(
            title: name,
            subtitle: "",
            thumbnail: nil,
            artwork: nil,
            content: MediaContent(service: .deezer, id: newID, type: .playlist, location: URL(string: "https://www.deezer.com/playlist/\(newID)")),
            metadata: nil
        )
    }

    /// Adds a track to a Deezer playlist.
    public func addToDeezerPlaylist(track: PlayableContent, playlistID: String) async -> Bool {
        guard let token = await deezerToken() else { return false }
        return await deezer.addTracks(playlistID: playlistID, trackIDs: [track.content.id], accessToken: token)
    }

    /// Removes a track from a Deezer playlist.
    public func removeFromDeezerPlaylist(track: PlayableContent, playlistID: String) async -> Bool {
        guard let token = await deezerToken() else { return false }
        return await deezer.removeTracks(playlistID: playlistID, trackIDs: [track.content.id], accessToken: token)
    }

    /// Deletes a Deezer playlist.
    public func deleteDeezerPlaylist(playlistID: String) async -> Bool {
        guard let token = await deezerToken() else { return false }
        return await deezer.deletePlaylist(playlistID: playlistID, accessToken: token)
    }

    // MARK: Service-agnostic dispatch

    /// The user's editable playlists for `service`, as `PlayableContent`.
    public func userPlaylists(for service: MusicService) async -> [PlayableContent] {
        switch service {
        case .apple: return await appleUserPlaylists()
        case .spotify: return await spotifyEditablePlaylists()
        case .plex: return await plexUserPlaylists()
        case .deezer: return await deezerEditablePlaylists()
        default: return []
        }
    }

    /// Creates a new playlist on `service`, optionally seeded with `track`.
    public func createServicePlaylist(name: String, seededWith track: PlayableContent? = nil, for service: MusicService) async -> PlayableContent? {
        switch service {
        case .apple: return await createApplePlaylist(name: name, addingTrack: track)
        case .spotify: return await createSpotifyPlaylist(name: name, addingTrack: track)
        case .deezer: return await createDeezerPlaylist(name: name, track: track)
        case .plex: return await createPlexPlaylist(name: name, track: track)
        default: return nil
        }
    }

    /// Whether `service` supports creating an empty playlist (no seed track).
    public static func supportsEmptyPlaylistCreation(_ service: MusicService) -> Bool {
        [.apple, .spotify, .deezer, .plex, .library].contains(service)
    }

    /// Deletes `playlist`, dispatching to its service. Apple Music has no delete API.
    public func deleteServicePlaylist(_ playlist: PlayableContent) async -> Bool {
        switch playlist.content.service {
        case .spotify: return await deleteSpotifyPlaylist(playlistID: playlist.content.id)
        case .plex: return await deletePlexPlaylist(playlistID: playlist.content.id)
        case .deezer: return await deleteDeezerPlaylist(playlistID: playlist.content.id)
        default: return false
        }
    }

    /// Adds `track` to `playlist`, dispatching to the playlist's service.
    public func addToServicePlaylist(track: PlayableContent, playlist: PlayableContent) async -> Bool {
        switch playlist.content.service {
        case .apple: return await addToApplePlaylist(track: track, playlistID: playlist.content.id)
        case .spotify: return await addToSpotifyPlaylist(track: track, playlistID: playlist.content.id)
        case .plex: return await addToPlexPlaylist(track: track, playlistID: playlist.content.id)
        case .deezer: return await addToDeezerPlaylist(track: track, playlistID: playlist.content.id)
        default: return false
        }
    }

    /// Removes `track` from `playlist`, dispatching to the playlist's service.
    /// Apple Music has no remove endpoint, so it returns `false`.
    ///
    /// `position` is the track's index within the playlist, used by Spotify to remove a single
    /// occurrence rather than every copy. Plex already targets a unique per-row id; Deezer's API
    /// only removes by track id, so it ignores `position`.
    public func removeFromServicePlaylist(track: PlayableContent, playlist: PlayableContent, position: Int? = nil) async -> Bool {
        switch playlist.content.service {
        case .spotify: return await removeFromSpotifyPlaylist(track: track, playlistID: playlist.content.id, position: position)
        case .plex: return await removeFromPlexPlaylist(track: track, playlistID: playlist.content.id)
        case .deezer: return await removeFromDeezerPlaylist(track: track, playlistID: playlist.content.id)
        default: return false
        }
    }

    /// Whether the authenticated user can edit `playlist`. Used to gate the editing UI, since
    /// streaming services let you browse playlists you can't modify. Apple Music has no edit API.
    public func canEditServicePlaylist(_ playlist: PlayableContent) async -> Bool {
        let id = playlist.content.id
        switch playlist.content.service {
        case .spotify:
            // Fast path: derive from the playlist's own owner/collaborative (one lookup + cached
            // user id). Fall back to membership in the editable list if it can't be confirmed.
            if let me = await cachedSpotifyUserID(),
               await spotifySearchAPI.isPlaylistEditable(id: id, currentUserID: me) {
                return true
            }
            return await editablePlaylistIDs(for: .spotify).contains(id)
        case .deezer:
            // Deezer only lets you edit playlists you own (the library list also includes followed
            // playlists), so confirm ownership rather than membership.
            guard let me = await cachedDeezerUserID() else { return false }
            return await deezer.isPlaylistEditable(id: id, ownedBy: me)
        case .plex:
            return true // Plex playlists live on the user's own server.
        default:
            return false
        }
    }

    /// The authenticated Spotify user id, cached for the session.
    private func cachedSpotifyUserID() async -> String? {
        if let spotifyUserID { return spotifyUserID }
        spotifyUserID = await spotifySearchAPI.currentUser()?.id
        return spotifyUserID
    }

    /// The authenticated Deezer user id, cached for the session.
    private func cachedDeezerUserID() async -> Int? {
        if let deezerUserID { return deezerUserID }
        guard let token = await deezerToken() else { return nil }
        deezerUserID = await deezer.currentUserID(accessToken: token)
        return deezerUserID
    }

    /// The cached set of editable Spotify playlist ids, fetching once if cold. (Spotify uses this as
    /// a fallback to the owner check; other services confirm editability directly.)
    private func editablePlaylistIDs(for service: MusicService) async -> Set<String> {
        if let cached = editablePlaylistIDsCache[service] { return cached }
        if service == .spotify { _ = await spotifyEditablePlaylists() } // populates the cache
        return editablePlaylistIDsCache[service] ?? []
    }

    /// Reorders a track within `playlist`. `orderedTracks` is the desired final order and
    /// `from`/`to` are the SwiftUI move offsets (source index and destination offset).
    ///
    /// Supported where the move is positional or item-based: Spotify (range move) and Plex
    /// (move-after-item). Apple Music has no reorder endpoint, and Deezer's only takes a full
    /// track-id list, which would truncate a paginated (partially loaded) playlist — so both
    /// return `false`.
    public func reorderServicePlaylist(playlist: PlayableContent, orderedTracks: [PlayableContent], from: Int, to: Int) async -> Bool {
        switch playlist.content.service {
        case .spotify:
            return await spotifySearchAPI.reorderPlaylistItems(playlistID: playlist.content.id, rangeStart: from, insertBefore: to)
        case .plex:
            let finalIndex = to > from ? to - 1 : to
            guard orderedTracks.indices.contains(finalIndex),
                  let playlistKey = plexRatingKey(from: playlist.content.id),
                  let movedItemID = orderedTracks[finalIndex].metadata?.playlistItemID else { return false }
            let afterItemID = finalIndex > 0 ? orderedTracks[finalIndex - 1].metadata?.playlistItemID : nil
            // For a non-front move we need the preceding item's id; if it's missing, fail rather
            // than silently moving the track to the front of the playlist.
            if finalIndex > 0, afterItemID == nil { return false }
            return await plex.movePlaylistItem(playlistRatingKey: playlistKey, playlistItemID: movedItemID, afterItemID: afterItemID)
        default:
            return false
        }
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
        if let artists = results.artists?.items {
            playableContent.append(contentsOf: artists.map(\.toPlayable))
            // Spotify has no radio catalog to search, but Sonos can start a
            // Spotify artist radio — surface one for the top artist matches,
            // like Apple's radio stations in its results. Appended after the
            // artists so equal-scoring radios rank below the artist itself.
            playableContent.append(contentsOf: artists.prefix(2).map { $0.toPlayable.toRadio })
        }
        if let tracks = results.playlists?.items {
            playableContent.append(contentsOf: tracks.compactMap { $0?.toPlayable })
        }

        playableContent = await enrichSpotifyAlbums(playableContent)

        return sortContentByIntelligentSearch(playableContent: playableContent, query: query)
    }

    /// Spotify's search API returns simplified albums with no popularity and
    /// no explicit flag, which buried albums below every popular track
    /// (searching "frozen" ranked the soundtrack far down). A batch full-album
    /// lookup fills in popularity for ranking and derives the explicit badge
    /// from the album's tracks.
    private func enrichSpotifyAlbums(_ playableContent: [PlayableContent]) async -> [PlayableContent] {
        let albumIDs = playableContent
            .filter { $0.content.service == .spotify && $0.content.type == .album }
            .map(\.id)
        guard !albumIDs.isEmpty else { return playableContent }

        let details = await spotifySearchAPI.albums(ids: albumIDs)
        guard !details.isEmpty else { return playableContent }
        let detailsByID = Dictionary(details.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return playableContent.map { item in
            guard item.content.type == .album, let detail = detailsByID[item.id] else { return item }
            var enriched = item
            enriched.metadata = item.metadata?.replacing(popularity: detail.popularity, isExplicit: detail.containsExplicitTracks)
                ?? PlayableContentMetadata(popularity: detail.popularity, isExplicit: detail.containsExplicitTracks)
            return enriched
        }
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
        request.includeTopResults = true
        request.limit = 20

        if let results = try? await request.response() {
            playableContent.append(contentsOf: results.songs.map(\.toPlayable))
            playableContent.append(contentsOf: results.albums.map(\.toPlayable))
            playableContent.append(contentsOf: results.artists.map(\.toPlayable))
            playableContent.append(contentsOf: results.playlists.map { $0.toPlayable(isUserPlaylist: false) })

            // MusicKit reports no popularity; Apple's editorial Top Results are
            // the equivalent signal. Unwrap them directly (rather than matching
            // ids against the typed lists) and surface each with descending
            // synthetic popularity (90, 85, …) so Apple's picks rank like the
            // other services' hits and the top-artist slot can trust them. The
            // sort's dedup collapses each against its plain copy, keeping the
            // boosted one — and a Top Result not present in the typed lists now
            // appears at all.
            for (rank, topResult) in results.topResults.prefix(5).enumerated() {
                let popularity = 90 - rank * 5
                let content: PlayableContent?
                switch topResult {
                case .song(let song): content = song.toPlayable
                case .album(let album): content = album.toPlayable
                case .artist(let artist): content = artist.toPlayable
                case .playlist(let playlist): content = playlist.toPlayable(isUserPlaylist: false)
                default: content = nil
                }
                if let content {
                    playableContent.append(withPopularity(content, popularity))
                }
            }
        }

        if let stations = try? await radioResults {
            playableContent.append(contentsOf: stations.data.compactMap(\.toPlayable))
        }

        // Unranked: searchApple (the only caller) ranks the combined
        // library+catalog list once — ranking here too was pure waste
        // (every intermediate order is discarded by the final sort).
        return playableContent
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

        // Unranked: searchApple (the only caller) ranks the combined list.
        return playableContent
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

    /// Converts a MusicKit track sequence to PlayableContent, enriching each Song
    /// with its previewAssets.
    ///
    /// Songs returned via an album/playlist `.tracks` relationship don't carry
    /// `previewAssets`, so we batch-fetch the missing ones with catalog resource
    /// requests. The Apple Music catalog `ids` parameter is capped per request,
    /// so IDs are chunked — otherwise a long playlist would exceed the cap and
    /// the whole request would fail, leaving every track without a preview.
    public func tracksToPlayableWithPreviews(_ tracks: some Sequence<MusicKit.Track>) async -> [PlayableContent] {
        // Apple Music caps the number of ids per catalog resource request.
        let batchSize = 100

        let trackArray = Array(tracks)

        var previewURLs: [MusicItemID: URL] = [:]

        // Skip the network round trip for songs that already carry a preview.
        var missingIDs: [MusicItemID] = []
        for track in trackArray {
            guard case .song(let song) = track else { continue }
            if let url = song.previewAssets?.first?.url {
                previewURLs[song.id] = url
            } else {
                missingIDs.append(song.id)
            }
        }

        for chunk in stride(from: 0, to: missingIDs.count, by: batchSize) {
            let ids = Array(missingIDs[chunk..<min(chunk + batchSize, missingIDs.count)])
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: ids)
            if let response = try? await request.response() {
                for song in response.items {
                    if let url = song.previewAssets?.first?.url {
                        previewURLs[song.id] = url
                    }
                }
            }
        }

        return trackArray.map { track in
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

        // Some servers omit detail from hub-search responses — a track's
        // Media element (codec/bitrate) and an album's leafCount — which is
        // exactly what tells duplicate editions apart. Fill the gaps with one
        // batch metadata lookup covering every item that came back without.
        var tracks = results.tracks
        var albums = results.album
        let tracksMissingMedia = tracks.filter { $0.audioCodec == nil && $0.bitrate == nil }.map(\.ratingKey)
        let albumsMissingCount = albums.filter { $0.leafCount == nil }.map(\.ratingKey)
        if !tracksMissingMedia.isEmpty || !albumsMissingCount.isEmpty {
            let metadataByKey = await plex.batchMetadata(ratingKeys: tracksMissingMedia + albumsMissingCount)
            for index in tracks.indices {
                guard let media = metadataByKey[tracks[index].ratingKey]?.media?.first else { continue }
                tracks[index].audioCodec = tracks[index].audioCodec ?? media.audioCodec
                tracks[index].bitrate = tracks[index].bitrate ?? media.bitrate
                tracks[index].audioChannels = tracks[index].audioChannels ?? media.audioChannels
                tracks[index].duration = tracks[index].duration ?? media.duration
            }
            for index in albums.indices {
                albums[index].leafCount = albums[index].leafCount ?? metadataByKey[albums[index].ratingKey]?.leafCount
            }
        }

        playableContent.append(contentsOf: tracks.map(\.toPlayable))
        playableContent.append(contentsOf: albums.map(\.toPlayable))
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
        // Ranking is safe here now that score ties preserve TuneIn's own
        // order — exact station-name matches float, the rest stay put.
        return sortContentByIntelligentSearch(playableContent: playableContent, query: query)
    }

    public func lookupTuneInStation(id: String) async -> TuneInStation? {
        await tuneIn.lookupStation(for: id)
    }

    // MARK: - Sonos Radio

    /// Resolves the Sonos Radio SMAPI endpoint (cached) and credentials needed
    /// for browse/search calls. Returns `nil` if Sonos Radio isn't available in
    /// the household or credentials can't be read.
    private func sonosRadioContext() async -> (endpoint: URL, credentials: SMAPICredentials)? {
        // Credentials. Sonos Radio is auto-provisioned on every household; its
        // loginToken is parsed off the system like any other service account.
        // SMAPI needs the controller deviceId alongside the loginToken.
        guard let creds = try? await KeychainTokenRefreshHandler.shared.getCredentials(for: .sonosRadio),
              !creds.token.isEmpty else {
            return nil
        }
        let credentials = SMAPICredentials(
            token: creds.token,
            key: creds.key,
            householdId: creds.householdId,
            deviceId: creds.deviceId
        )

        // Endpoint. Mirror the proven Deezer pattern (hardcoded SMAPI host);
        // fall back to dynamic ListAvailableServices discovery only if needed.
        // The host below is the Sonos Radio SMAPI endpoint seen in the official
        // controller's traffic.
        let endpoint: URL
        if let cached = cachedSonosRadioEndpoint {
            endpoint = cached
        } else if let resolved = await sonosService.smapiEndpoint(for: Self.sonosRadioServiceID) {
            endpoint = resolved
        } else if let fallback = URL(string: "https://sali.sonos.superhi.fi/smapi") {
            endpoint = fallback
        } else {
            return nil
        }
        cachedSonosRadioEndpoint = endpoint
        return (endpoint, credentials)
    }

    private func searchSonosRadio(query: String) async -> [PlayableContent] {
        await sonosRadioStations(matching: query)
    }

    /// Browses a Sonos Radio SMAPI container. `"root"` exposes the dynamic
    /// home sections the official controller shows ("Trending Now",
    /// "Summertime", …); each section container's children are stations.
    /// Returns `nil` if Sonos Radio isn't reachable for the household.
    public func sonosRadioBrowse(id: String, index: Int = 0, count: Int = 100) async -> SMAPIMediaResult? {
        guard let (endpoint, credentials) = await sonosRadioContext() else { return nil }
        return await sonosRadio.getMetadata(
            endpoint: endpoint,
            credentials: credentials,
            id: id,
            index: index,
            count: count
        )
    }

    /// The playable stations inside a Sonos Radio container, mapped to
    /// `PlayableContent`. Nested non-playable containers are skipped.
    public func sonosRadioContainerStations(id: String, count: Int = 100) async -> [PlayableContent] {
        guard let result = await sonosRadioBrowse(id: id, count: count) else { return [] }
        return result.items
            .filter { $0.canPlay || !$0.isContainer }
            .map { createSonosRadioContent(from: $0) }
    }

    /// Searches Sonos Radio stations for `term` via the "station" search
    /// category. Powers search and the genre fallback on the browse screen.
    public func sonosRadioStations(matching term: String, count: Int = 50) async -> [PlayableContent] {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, let (endpoint, credentials) = await sonosRadioContext() else { return [] }
        guard let result = await sonosRadio.search(endpoint: endpoint, credentials: credentials, id: "station", term: term, count: count) else { return [] }
        return result.items.map { createSonosRadioContent(from: $0) }
    }

    private func createSonosRadioContent(from item: SMAPIMediaItem) -> PlayableContent {
        let artworkURL = item.albumArtURI.flatMap { URL(string: $0) }
        let subtitle = item.artist ?? item.summary ?? "Sonos Radio"
        return PlayableContent(
            title: item.title,
            subtitle: subtitle,
            thumbnail: artworkURL,
            artwork: artworkURL,
            content: MediaContent(
                service: .sonosRadio,
                id: item.id,
                type: .radio,
                location: nil
            ),
            metadata: .init(
                artist: item.artist,
                album: item.album,
                radioStation: true
            )
        )
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
        SearchRanking.sort(playableContent, query: query, recentlyPlayedIDs: recentlyPlayedIDs)
    }

    /// Returns `content` with its metadata's popularity set (preserving the
    /// rest), for grafting a synthetic quality signal — e.g. Apple Top Results.
    private func withPopularity(_ content: PlayableContent, _ popularity: Int) -> PlayableContent {
        var updated = content
        updated.metadata = (content.metadata ?? PlayableContentMetadata())
            .replacing(popularity: popularity, isExplicit: content.metadata?.isExplicit)
        return updated
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

    /// The user's *owned* Deezer playlists (creator == current user). `/user/me/playlists` also
    /// returns followed playlists, which can't be edited — so the editing/add surfaces filter to
    /// owned ones, mirroring Spotify's editable-only list.
    public func deezerEditablePlaylists() async -> [PlayableContent] {
        guard let token = await deezerToken(),
              let me = await cachedDeezerUserID() else { return [] }
        return await deezer.userPlaylists(accessToken: token, index: 0)
            .filter { $0.creator?.id == me }
            .map { createDeezerPlaylistContent(from: $0) }
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
        let subtitle = [
            artistName.isEmpty ? nil : artistName,
            album.releaseYear,
            album.nbTracks.flatMap(\.songCountLabel)
        ].compactMap { $0 }.joined(separator: " • ")
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
            subtitle: playlist.creator?.name ?? "",
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
