import Foundation
import MusicKit
import MusicSearchKit
import Observation
import SonosKit

/// One song of the playlist being imported, and what it was matched to.
struct ImportRow: Identifiable {
    enum State: Equatable {
        /// Not looked for yet.
        case pending
        /// Found: the same song.
        case matched
        /// Found something that's probably it — another version, or a
        /// different length. Added, and worth a look.
        case check
        /// Nothing close enough to add on its own.
        case missing
        /// Picked by hand.
        case chosen
        /// Left out by hand.
        case skipped
    }

    let track: ImportedTrack
    var id: Int { track.id }
    var state: State = .pending
    /// What the matcher found, best first.
    var matches: [SongMatch<PlayableContent>] = []
    /// What goes into the playlist, or nil for nothing.
    var choice: PlayableContent?
}

/// Brings a playlist from Spotify, Apple Music or a file into a service Cue
/// plays: reads it, finds each song on that service, lets the user settle
/// the ones it isn't sure of, then makes the playlist there.
///
/// Matching runs against the service's own song list where Cue keeps one
/// (Plex, Subsonic and Files are synced or indexed on the device, so a
/// thousand songs take no requests at all) and against Apple Music's catalog
/// search otherwise, ISRC first where the source gave one.
@MainActor
@Observable
final class PlaylistImporter {
    enum Phase: Equatable {
        case start
        case reading
        case matching
        case review
        case creating
        case done(PlayableContent)
    }

    private(set) var phase: Phase = .start
    private(set) var playlist: ImportedPlaylist?
    private(set) var rows: [ImportRow] = []
    /// Rows looked up so far in the current match.
    private(set) var progress = 0
    var name = ""
    var errorMessage: String?
    /// The service the playlist is made on. Changing it after the songs were
    /// matched matches them again there.
    var destination: MusicService {
        didSet {
            guard destination != oldValue, playlist != nil else { return }
            startMatching()
        }
    }

    @ObservationIgnored private var work: Task<Void, Never>?
    private let musicSearchService = MusicSearchService.shared

    init(destination: MusicService? = nil) {
        self.destination = destination.flatMap { Self.destinations.contains($0) ? $0 : nil }
            ?? Self.destinations.first
            ?? .apple
    }

    // MARK: - Destinations

    /// The services a playlist can be made on: those Cue plays, with
    /// playlists of their own, that are set up.
    static var destinations: [MusicService] {
        let features = CoreFeatures.shared
        let search = MusicSearchService.shared
        var services: [MusicService] = []
        if features.isEnabled(.apple), MusicAuthorization.currentStatus != .denied, MusicAuthorization.currentStatus != .restricted {
            services.append(.apple)
        }
        if features.isEnabled(.plex), search.isPlexAuthorized, search.plexServerID != nil {
            services.append(.plex)
        }
        if features.isEnabled(.subsonic), search.isSubsonicConfigured {
            services.append(.subsonic)
        }
        if features.isEnabled(.files), search.isFilesConfigured {
            services.append(.files)
        }
        return services
    }

    // MARK: - Counts

    var addedCount: Int { rows.filter { $0.choice != nil }.count }
    var checkCount: Int { rows.filter { $0.state == .check }.count }
    var missingCount: Int { rows.filter { $0.state == .missing }.count }

    /// Songs of the destination's library read so far, while Cue is reading
    /// it for the first time — a large Plex or Subsonic library takes a
    /// while, and matching waits on it.
    var librarySyncCount: Int? {
        switch destination {
        case .plex: musicSearchService.isSyncingPlexSongs ? musicSearchService.plexSyncedSongCount : nil
        case .subsonic: musicSearchService.isSyncingSubsonicSongs ? musicSearchService.subsonicSyncedSongCount : nil
        default: nil
        }
    }

    // MARK: - Reading

    /// A link, or a list of songs pasted as text.
    func load(text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        read {
            if let link = PlaylistLink(text) {
                return try await Self.read(link)
            }
            // Several lines that aren't links: "Artist - Title" a line.
            if text.contains(where: \.isNewline), let pasted = PlaylistFileParser.parse(text, fileName: "Pasted Songs") {
                return pasted
            }
            throw PlaylistImportError.unsupported
        }
    }

    /// A CSV, M3U or text file the user picked.
    func load(file url: URL) {
        read {
            let data = try Self.contents(of: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252),
                  let playlist = PlaylistFileParser.parse(text, fileName: url.lastPathComponent) else {
                throw PlaylistImportError.empty
            }
            return playlist
        }
    }

    /// One of the user's Apple Music playlists.
    func load(applePlaylist: PlayableContent) {
        read {
            try await AppleMusicPlaylistReader.read(libraryPlaylist: applePlaylist)
        }
    }

    private func read(_ reader: @escaping @MainActor () async throws -> ImportedPlaylist) {
        work?.cancel()
        errorMessage = nil
        phase = .reading
        work = Task {
            do {
                let playlist = try await reader()
                guard !Task.isCancelled else { return }
                self.playlist = playlist
                name = playlist.name
                startMatching()
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                phase = .start
            }
        }
    }

    private static func read(_ link: PlaylistLink) async throws -> ImportedPlaylist {
        let spotify = SpotifyPlaylistReader()
        switch link {
        case let .spotify(kind, id):
            return try await spotify.read(kind, id: id)
        case let .spotifyTracks(ids):
            return try await spotify.read(trackIDs: ids)
        case let .spotifyShortLink(url):
            guard let resolved = await spotify.resolve(shortLink: url), resolved != link else {
                throw PlaylistImportError.notFound
            }
            return try await read(resolved)
        case .appleMusic, .appleMusicLibrary:
            return try await AppleMusicPlaylistReader.read(link)
        }
    }

    /// A picked file's bytes. Files from the picker are outside the sandbox
    /// until access is asked for.
    private nonisolated static func contents(of url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw PlaylistImportError.unreachable
        }
    }

    // MARK: - Matching

    func startMatching() {
        guard let playlist else { return }
        work?.cancel()
        errorMessage = nil
        rows = playlist.tracks.map { ImportRow(track: $0) }
        progress = 0
        phase = .matching
        let service = destination
        work = Task {
            switch service {
            case .apple:
                await matchAppleMusic(playlist.tracks)
            default:
                await matchLibrary(playlist.tracks, on: service)
            }
            guard !Task.isCancelled else { return }
            phase = .review
        }
    }

    /// Settles a row with what the matcher found.
    private func record(_ matches: [SongMatch<PlayableContent>], for index: Int) {
        guard rows.indices.contains(index) else { return }
        rows[index].matches = matches
        switch matches.first?.confidence {
        case .high?:
            rows[index].state = .matched
            rows[index].choice = matches.first?.item
        case .medium?:
            rows[index].state = .check
            rows[index].choice = matches.first?.item
        default:
            rows[index].state = .missing
            rows[index].choice = nil
        }
        progress += 1
    }

    /// Plex, Subsonic and Files: every song is already on the device, so
    /// each track is looked up in an index of them.
    private func matchLibrary(_ tracks: [ImportedTrack], on service: MusicService) async {
        let library = await songs(on: service)
        guard !Task.isCancelled else { return }
        guard !library.isEmpty else {
            // No copy of the library (the sync failed, or a server that
            // won't list everything): ask the server, one title at a time.
            await matchBySearching(tracks) { [musicSearchService] track in
                let term = SongMatcher.searchTerm(for: track, includingArtist: false)
                switch service {
                case .plex: return await musicSearchService.searchPlexSongs(query: term)
                case .subsonic: return await musicSearchService.searchSubsonicSongs(query: term)
                default: return []
                }
            }
            return
        }

        let index = await Task.detached(priority: .userInitiated) {
            SongIndex(library, fields: Self.candidate)
        }.value
        // In slices off the main actor, so the rows fill in as it goes.
        for start in stride(from: 0, to: tracks.count, by: 25) {
            guard !Task.isCancelled else { return }
            let slice = Array(tracks[start..<min(start + 25, tracks.count)])
            let found = await Task.detached(priority: .userInitiated) {
                slice.map { index.matches(for: $0) }
            }.value
            // Matching started over meanwhile: these rows are gone.
            guard !Task.isCancelled else { return }
            for (offset, matches) in found.enumerated() {
                record(matches, for: start + offset)
            }
        }
    }

    private func songs(on service: MusicService) async -> [PlayableContent] {
        switch service {
        case .plex:
            return await musicSearchService.plexSongs()
        case .subsonic:
            return await musicSearchService.subsonicSongs()
        case .files:
            await FilesLibraryService.shared.scanIfNeeded()
            return FilesLibraryService.shared.songs
        default:
            return []
        }
    }

    /// Apple Music: the catalog, by ISRC where the source gave one, then by
    /// searching for the title and artist.
    private func matchAppleMusic(_ tracks: [ImportedTrack]) async {
        guard await musicSearchService.requestMusicAuthorization() else {
            errorMessage = PlaylistImportError.appleMusicNotAuthorized.localizedDescription
            return
        }
        let byISRC = await Self.appleSongs(isrcs: tracks.compactMap(\.isrc))
        await matchBySearching(tracks) { track in
            if let isrc = track.isrc?.uppercased(), let songs = byISRC[isrc] {
                let ranked = SongMatcher.rank(track, among: songs, fields: Self.candidate)
                if ranked.first?.confidence == .high { return songs }
            }
            let found = await Self.searchAppleMusic(SongMatcher.searchTerm(for: track))
            if SongMatcher.rank(track, among: found, fields: Self.candidate).first?.confidence ?? .low >= .medium {
                return found
            }
            // The artist may be written differently there ("Beyoncé" for
            // "Beyonce", a band's full name): the title alone, then judged.
            return found + (await Self.searchAppleMusic(SongMatcher.searchTerm(for: track, includingArtist: false)))
        }
    }

    /// Looks each track up with `search`, a few at a time, and ranks what
    /// comes back.
    private func matchBySearching(
        _ tracks: [ImportedTrack],
        search: @escaping @MainActor (ImportedTrack) async -> [PlayableContent]
    ) async {
        await withTaskGroup(of: (Int, [SongMatch<PlayableContent>]).self) { group in
            var next = 0
            func enqueue() {
                guard next < tracks.count, !Task.isCancelled else { return }
                let index = next
                let track = tracks[index]
                next += 1
                group.addTask { @MainActor in
                    var seen = Set<String>()
                    let candidates = await search(track).filter { $0.isPlayable && seen.insert($0.id).inserted }
                    return (index, SongMatcher.rank(track, among: candidates, fields: Self.candidate).prefix(5).map { $0 })
                }
            }
            for _ in 0..<4 { enqueue() }
            for await (index, matches) in group {
                // Matching started over meanwhile: these rows are gone.
                guard !Task.isCancelled else { continue }
                record(matches, for: index)
                enqueue()
            }
        }
    }

    private static func searchAppleMusic(_ term: String) async -> [PlayableContent] {
        guard !term.isEmpty else { return [] }
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
        request.limit = 10
        guard let response = try? await request.response() else { return [] }
        return response.songs.map(\.toPlayable)
    }

    /// Catalog songs for the ISRCs, by ISRC. The catalog takes 25 at a time.
    private static func appleSongs(isrcs: [String]) async -> [String: [PlayableContent]] {
        let codes = Array(Set(isrcs.map { $0.uppercased() }))
        var songs: [String: [PlayableContent]] = [:]
        for start in stride(from: 0, to: codes.count, by: 25) {
            guard !Task.isCancelled else { break }
            let batch = Array(codes[start..<min(start + 25, codes.count)])
            let request = MusicCatalogResourceRequest<Song>(matching: \.isrc, memberOf: batch)
            guard let response = try? await request.response() else { continue }
            for song in response.items {
                guard let isrc = song.isrc?.uppercased() else { continue }
                songs[isrc, default: []].append(song.toPlayable)
            }
        }
        return songs
    }

    nonisolated static func candidate(_ content: PlayableContent) -> SongCandidate {
        SongCandidate(
            title: content.title,
            artist: content.metadata?.artist ?? content.subtitle,
            album: content.metadata?.album,
            duration: content.metadata?.duration.map(\.seconds),
            isrc: content.metadata?.isrc
        )
    }

    // MARK: - Settling rows

    func choose(_ content: PlayableContent, for rowID: Int) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].choice = content
        rows[index].state = .chosen
    }

    func skip(_ rowID: Int) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].choice = nil
        rows[index].state = .skipped
    }

    /// Keeps every "check" row's match as it is.
    func acceptAllToCheck() {
        for index in rows.indices where rows[index].state == .check {
            rows[index].state = .chosen
        }
    }

    /// Songs on the destination for a search typed by hand, for a row the
    /// matcher couldn't settle.
    func search(_ query: String) async -> [PlayableContent] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        switch destination {
        case .apple:
            return await Self.searchAppleMusic(query).filter(\.isPlayable)
        case .plex:
            return await musicSearchService.searchPlexSongs(query: query)
        case .subsonic:
            return await musicSearchService.searchSubsonicSongs(query: query)
        case .files:
            return FilesLibraryService.shared.search(query: query).filter { $0.content.type == .track }
        default:
            return []
        }
    }

    // MARK: - Creating

    /// Makes the playlist on the destination with every row that has a song.
    func create() async {
        let songs = rows.compactMap(\.choice)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = songs.first, !name.isEmpty else { return }
        work?.cancel()
        errorMessage = nil
        phase = .creating
        progress = 0

        guard let created = await musicSearchService.createServicePlaylist(name: name, seededWith: first, for: destination) else {
            errorMessage = "The playlist couldn’t be made on \(destination.title). Try again."
            phase = .review
            return
        }
        progress = 1
        let added = await musicSearchService.addToServicePlaylist(tracks: Array(songs.dropFirst()), playlist: created) + 1
        progress = added
        if added < songs.count {
            errorMessage = "\(songs.count - added) of \(songs.count) songs couldn’t be added."
        }
        insertIntoBrowseList(created)
        LastPlaylist.save(created)
        phase = .done(created)
    }

    /// Shows the new playlist in the service's list straight away, as
    /// creating one by hand does.
    private func insertIntoBrowseList(_ playlist: PlayableContent) {
        switch destination {
        case .apple: AppleMusicBrowseService.shared.userPlaylists.insert(playlist, at: 0)
        case .plex: PlexBrowseService.shared.userPlaylists.insert(playlist, at: 0)
        case .subsonic: SubsonicBrowseService.shared.userPlaylists.insert(playlist, at: 0)
        default: break
        }
    }

    // MARK: - Leaving

    /// Back to the start, to import something else.
    func reset() {
        work?.cancel()
        playlist = nil
        rows = []
        progress = 0
        name = ""
        errorMessage = nil
        phase = .start
    }

    func cancel() {
        work?.cancel()
    }
}

private extension Duration {
    var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
