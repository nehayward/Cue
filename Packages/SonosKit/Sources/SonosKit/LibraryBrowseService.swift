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

    /// Fetches one page of songs starting at `offset`. Returns `true` when a
    /// full page was returned, indicating more items may be available.
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
