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

    public init() { }

    public func updateSongs(offset: Int = 0) async {
        guard let ip = sonosService.prioritizedIP() else { return }
        let newSongs = await sonosAPI.getLibraryItems(IP: ip, type: .track, offset: offset, requestedCount: 500)
        for newSong in newSongs {
            songs.updateOrAppend(newSong)
        }
    }

    public func updateAlbum(offset: Int = 0) async {
        guard let ip = sonosService.prioritizedIP() else { return }
        let newAlbums = await sonosAPI.getLibraryItems(IP: ip, type: .album, offset: offset, requestedCount: 500)
        for newAlbum in newAlbums {
            albums.updateOrAppend(newAlbum)
        }
    }

    public func updateArtists(offset: Int = 0) async {
        guard let ip = sonosService.prioritizedIP() else { return }
        let newArtists = await sonosAPI.getLibraryItems(IP: ip, type: .artist, offset: offset, requestedCount: 500)
        for newArtist in newArtists {
            artists.updateOrAppend(newArtist)
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
}
