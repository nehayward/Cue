import Foundation
import MusicKit
import MusicSearchKit

@Observable
public final class BrowseService {
    public static var shared = BrowseService()
    public var appleMusicAuthorizationStatus: AppleMusicAuthorization = .denied
    public var plexAuthorization: AppleMusicAuthorization = .denied

    @ObservationIgnored private let appleMusicSearchAPI = AppleMusicSearchAPI()
    @ObservationIgnored private let apple = AppleMusicAPI()
    @ObservationIgnored private let plex = PlexAPI()
    @ObservationIgnored private let tidal = TidalAPI()
    @ObservationIgnored private let spotifySearchAPI = SpotifyAPI()
    @ObservationIgnored private let tuneIn = TuneInAPI()
    @ObservationIgnored private let sonosService = SonosService.shared
    @ObservationIgnored private let sonos = SonosAPI()

    public var artists: [PlayableContent] = []
    public var albums: [PlayableContent] = []
    public var playlists: [PlayableContent] = []
    public var songs: [PlayableContent] = []

    public init() { }

    public func updateArtists() async {
        guard let ip = sonosService.prioritizedIP() else { return }
        artists = await sonos.getLibraryItems(IP: ip, type: .artist)
    }

    public func updateAlbum() async {
        guard let ip = sonosService.prioritizedIP() else { return }
        albums = await sonos.getLibraryItems(IP: ip, type: .album)
    }

    public func updateSongs() async {
        guard let ip = sonosService.prioritizedIP() else { return }
        songs = await sonos.getLibraryItems(IP: ip, type: .track)
    }

    public func updatePlaylists() async {
        guard let ip = sonosService.prioritizedIP() else { return }
        playlists = await sonos.getLibraryItems(IP: ip, type: .playlist)
    }
}
