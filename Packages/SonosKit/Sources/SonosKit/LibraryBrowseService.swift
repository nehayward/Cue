import Foundation
import MusicKit
import MusicSearchKit
import OrderedCollections

/// An alphabetical bucket of library items (e.g. all albums under "D"),
/// precomputed so list views can render sections without regrouping per render.
public struct LibrarySection: Identifiable, Equatable {
    public let letter: String
    public let items: [PlayableContent]
    public var id: String { letter }
}

@Observable
public final class LibraryBrowseService {
    public static var shared = LibraryBrowseService()

    @ObservationIgnored private let sonosService = SonosService.shared
    @ObservationIgnored private let sonosAPI = SonosAPI()

    public var songs: OrderedSet<PlayableContent> = []
    public var artists: OrderedSet<PlayableContent> = []
    public var albums: OrderedSet<PlayableContent> = []
    public var genres: OrderedSet<PlayableContent> = []
    public var playlists: OrderedSet<PlayableContent> = []
    public var importedPlaylists: OrderedSet<PlayableContent> = []
    public var folders: OrderedSet<PlayableContent> = []

    /// Alphabetically grouped views of `albums` / `artists` / `playlists`,
    /// recomputed only when the underlying set changes (not on every render).
    public private(set) var albumSections: [LibrarySection] = []
    public private(set) var artistSections: [LibrarySection] = []
    public private(set) var playlistSections: [LibrarySection] = []

    public init() { }

    /// Number of items requested per `Browse` page. Sonos paginates the music
    /// library via `StartingIndex` / `RequestedCount`; callers fetch the next
    /// page as the user scrolls.
    @ObservationIgnored private let pageSize = 500

    // MARK: - Synced track list

    /// The whole track index, synced once and kept on disk. The speaker
    /// answers a page at a time, which is fine for scrolling and useless for
    /// searching — you can only search what you already hold.
    @ObservationIgnored private var songSync: Task<[PlayableContent], Never>?
    private static let songCache = LibraryCache<PlayableContent>(name: "SonosLibrary")
    public private(set) var isSyncingSongs = false
    public private(set) var syncedSongCount = 0
    public private(set) var librarySongCount: Int?
    /// How many tracks the library holds, once the copy is available.
    public private(set) var songCount: Int?

    /// One household's library. Pointing Clic at another system is another
    /// library, and its copy shouldn't be read back for this one.
    private var cacheOwner: String {
        KeychainTokenRefreshHandler.shared.householdId ?? ""
    }

    /// Every track, all at once — the copy is already here, so there is
    /// nothing to page.
    @MainActor
    public func allSongs(offset: Int = 0) async -> [PlayableContent] {
        guard offset == 0 else { return [] }
        return await songLibrary()
    }

    /// Tracks matching a query, filtered from the synced copy. The speaker's
    /// Browse has no query of its own for this index, which is the whole
    /// reason the copy exists.
    @MainActor
    public func searchSongs(query: String, offset: Int = 0) async -> [PlayableContent] {
        guard offset == 0 else { return [] }
        let songs = await songLibrary()
        return await Self.filtered(songs, query: query)
    }

    /// How much disk the synced index takes, for the Storage settings.
    public static var cachedSongLibrarySize: Int { songCache.sizeInBytes }

    @MainActor
    public func clearSongCache() {
        songSync?.cancel()
        songSync = nil
        syncedSongCount = 0
        librarySongCount = nil
        songCount = nil
        Self.songCache.clear()
    }

    /// Drops the copy when the speaker's index no longer has the same number
    /// of tracks, so a re-index or new files show up on the next visit.
    @MainActor
    public func refreshLibraryIfChanged() async {
        guard songSync != nil, let known = songCount, let ip = sonosService.prioritizedIP() else { return }
        guard let count = await sonosAPI.libraryItemCount(IP: ip, type: .track), count != known else { return }
        clearSongCache()
    }

    @MainActor
    private func songLibrary() async -> [PlayableContent] {
        if let inFlight = songSync { return await inFlight.value }

        let task = Task { await loadSongLibrary() }
        songSync = task
        let songs = await task.value
        if songs.isEmpty, songSync == task { songSync = nil }
        return songs
    }

    @MainActor
    private func loadSongLibrary() async -> [PlayableContent] {
        guard let ip = sonosService.prioritizedIP() else { return [] }

        isSyncingSongs = true
        syncedSongCount = 0
        defer { isSyncingSongs = false }

        let total = await sonosAPI.libraryItemCount(IP: ip, type: .track)
        librarySongCount = total

        if let cached = await Self.songCache.load(owner: cacheOwner), total == nil || cached.count == total {
            songCount = cached.count
            songs = OrderedSet(cached)
            return cached
        }

        let synced = await syncSongLibrary(ip: ip, total: total)
        if !synced.isEmpty {
            Self.songCache.save(synced, owner: cacheOwner)
            songCount = synced.count
            // Keep the paged property in step: other screens read it.
            songs = OrderedSet(synced)
        }
        return synced
    }

    /// Pages the index in. Sequential: these are SOAP requests to a speaker,
    /// not a server farm, and a few in flight buys little next to the risk of
    /// making it unresponsive while music is playing.
    @MainActor
    private func syncSongLibrary(ip: String, total: Int?) async -> [PlayableContent] {
        var collected: [PlayableContent] = []
        var seenIDs = Set<String>()
        var offset = 0

        while collected.count < Self.songSyncLimit {
            let page = await sonosAPI.getLibraryItems(IP: ip, type: .track, offset: offset, requestedCount: pageSize)
            guard !Task.isCancelled else { return [] }

            let before = collected.count
            collected.append(contentsOf: page.filter { seenIDs.insert($0.id).inserted })
            syncedSongCount = collected.count

            // A short page is the last one, and a page that added nothing new
            // means the speaker is repeating itself rather than advancing.
            if page.count < pageSize || collected.count == before { break }
            if let total, collected.count >= total { break }
            offset += pageSize
        }

        return collected
    }

    private nonisolated static func filtered(_ songs: [PlayableContent], query: String) async -> [PlayableContent] {
        songs.filter { song in
            [song.title, song.subtitle, song.metadata?.album ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// Ceiling on the synced copy, so an enormous shared library can't spend
    /// minutes paging before Songs draws a row.
    private static let songSyncLimit = 50_000

    /// Fetches one page of songs starting at `offset`. Returns `true` when a
    /// full page was returned, indicating more items may be available.
    @MainActor
    @discardableResult
    public func updateSongs(offset: Int = 0) async -> Bool {
        guard let ip = sonosService.prioritizedIP() else { return false }
        let newSongs = await sonosAPI.getLibraryItems(IP: ip, type: .track, offset: max(offset, 0), requestedCount: pageSize)
        for newSong in newSongs {
            songs.updateOrAppend(newSong)
        }
        return newSongs.count >= pageSize
    }

    /// Fetches one page of albums starting at `offset`. Returns `true` when a
    /// full page was returned, indicating more items may be available.
    @MainActor
    @discardableResult
    public func updateAlbum(offset: Int = 0) async -> Bool {
        guard let ip = sonosService.prioritizedIP() else { return false }
        let newAlbums = await sonosAPI.getLibraryItems(IP: ip, type: .album, offset: max(offset, 0), requestedCount: pageSize)
        for newAlbum in newAlbums {
            albums.updateOrAppend(newAlbum)
        }
        if !newAlbums.isEmpty {
            albumSections = Self.groupedSections(from: albums)
        }
        return newAlbums.count >= pageSize
    }

    /// Fetches one page of artists starting at `offset`. Returns `true` when a
    /// full page was returned, indicating more items may be available.
    @MainActor
    @discardableResult
    public func updateArtists(offset: Int = 0) async -> Bool {
        guard let ip = sonosService.prioritizedIP() else { return false }
        let newArtists = await sonosAPI.getLibraryItems(IP: ip, type: .artist, offset: max(offset, 0), requestedCount: pageSize)
        for newArtist in newArtists {
            artists.updateOrAppend(newArtist)
        }
        if !newArtists.isEmpty {
            artistSections = Self.groupedSections(from: artists)
        }
        return newArtists.count >= pageSize
    }
    
    @MainActor
    public func updateImportedPlaylists(offset: Int = 0) async {
        guard let ip = sonosService.prioritizedIP() else { return }
        let newArtists = await sonosAPI.getLibraryItems(IP: ip, type: "A:PLAYLISTS:", offset: offset, requestedCount: 500)
        for newArtist in newArtists {
            importedPlaylists.updateOrAppend(newArtist)
        }
    }


    /// Fetches one page of genres starting at `offset`. Returns `true` when a
    /// full page was returned, indicating more items may be available.
    @MainActor
    @discardableResult
    public func updateGenres(offset: Int = 0) async -> Bool {
        guard let ip = sonosService.prioritizedIP() else { return false }
        let items = await sonosAPI.getLibraryItems(IP: ip, type: "A:GENRE:", offset: offset, requestedCount: pageSize)
        for item in items {
            genres.updateOrAppend(item)
        }
        return items.count >= pageSize
    }

    @MainActor
    public func updatePlaylists() async {
        guard let ip = sonosService.prioritizedIP() else { return }
        let newPlaylists = await sonosAPI.getLibraryItems(IP: ip, type: .playlist, offset: 0, requestedCount: 0)
        playlists = OrderedSet(newPlaylists)
        playlistSections = Self.groupedSections(from: playlists)
    }

    /// Removes a playlist locally and refreshes the grouped sections.
    @MainActor
    public func removePlaylist(id: String) {
        playlists.removeAll { $0.id == id }
        playlistSections = Self.groupedSections(from: playlists)
    }

    /// Groups items into alphabetical sections sorted by leading letter,
    /// bucketing non-letter titles under "#". Computed once per data change.
    private static func groupedSections<S: Sequence>(from items: S) -> [LibrarySection] where S.Element == PlayableContent {
        let groups = Dictionary(grouping: items) { item -> String in
            guard let scalar = item.title
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .unicodeScalars
                .first,
                  CharacterSet.letters.contains(scalar)
            else { return "#" }

            return String(scalar).uppercased()
        }

        return groups.keys.sorted().map { LibrarySection(letter: $0, items: groups[$0] ?? []) }
    }
    
    @MainActor
    public func updateFolders(offset: Int = 0) async {
        guard let ip = sonosService.prioritizedIP() else { return }
        let newFolders = await sonosAPI.getLibraryItems(IP: ip, type: "S:", offset: offset, requestedCount: 500)
        for newFolder in newFolders {
            folders.updateOrAppend(newFolder)
        }
    }
    
    @MainActor
    public func browseFolder(folderID: String, offset: Int = 0) async -> [PlayableContent] {
        guard let ip = sonosService.prioritizedIP() else { return [] }
        return await sonosAPI.getLibraryItems(IP: ip, type: folderID, offset: offset, requestedCount: 500)
    }
}
