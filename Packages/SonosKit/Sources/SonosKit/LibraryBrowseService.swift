import Foundation
import MusicKit
import MusicSearchKit
import OrderedCollections

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

    public init() { }

    /// Number of items requested per `Browse` page. Sonos paginates the music
    /// library via `StartingIndex` / `RequestedCount`, so we loop through every
    /// page rather than relying on a single fixed-size request.
    @ObservationIgnored private let pageSize = 500

    public func updateSongs(offset: Int = 0) async {
        guard let ip = sonosService.prioritizedIP() else { return }
        var currentOffset = max(offset, 0)
        while true {
            let newSongs = await sonosAPI.getLibraryItems(IP: ip, type: .track, offset: currentOffset, requestedCount: pageSize)
            if newSongs.isEmpty { break }
            for newSong in newSongs {
                songs.updateOrAppend(newSong)
            }
            if newSongs.count < pageSize { break }
            currentOffset += newSongs.count
        }
    }

    public func updateAlbum(offset: Int = 0) async {
        guard let ip = sonosService.prioritizedIP() else { return }
        var currentOffset = max(offset, 0)
        while true {
            let newAlbums = await sonosAPI.getLibraryItems(IP: ip, type: .album, offset: currentOffset, requestedCount: pageSize)
            if newAlbums.isEmpty { break }
            for newAlbum in newAlbums {
                albums.updateOrAppend(newAlbum)
            }
            if newAlbums.count < pageSize { break }
            currentOffset += newAlbums.count
        }
    }

    public func updateArtists(offset: Int = 0) async {
        guard let ip = sonosService.prioritizedIP() else { return }
        var currentOffset = max(offset, 0)
        while true {
            let newArtists = await sonosAPI.getLibraryItems(IP: ip, type: .artist, offset: currentOffset, requestedCount: pageSize)
            if newArtists.isEmpty { break }
            for newArtist in newArtists {
                artists.updateOrAppend(newArtist)
            }
            if newArtists.count < pageSize { break }
            currentOffset += newArtists.count
        }
    }
    
    @MainActor
    public func updateImportedPlaylists(offset: Int = 0) async {
        guard let ip = sonosService.prioritizedIP() else { return }
        let newArtists = await sonosAPI.getLibraryItems(IP: ip, type: "A:PLAYLISTS:", offset: offset, requestedCount: 500)
        for newArtist in newArtists {
            importedPlaylists.updateOrAppend(newArtist)
        }
    }


    @MainActor
    public func updateGenres(offset: Int = 0) async {
        guard let ip = sonosService.prioritizedIP() else { return }
        let items = await sonosAPI.getLibraryItems(IP: ip, type: "A:GENRE:", offset: offset, requestedCount: 500)
        for item in items {
            genres.updateOrAppend(item)
        }
    }

    @MainActor
    public func updatePlaylists() async {
        guard let ip = sonosService.prioritizedIP() else { return }
        let newPlaylists = await sonosAPI.getLibraryItems(IP: ip, type: .playlist, offset: 0, requestedCount: 0)
        playlists = OrderedSet(newPlaylists)
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
