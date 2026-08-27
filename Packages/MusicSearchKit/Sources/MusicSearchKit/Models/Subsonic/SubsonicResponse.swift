import Foundation

/// Envelope every Subsonic REST response arrives in:
/// `{"subsonic-response": {"status": "ok", ..., "<payload>": {...}}}`.
struct SubsonicEnvelope: Decodable {
    let subsonicResponse: SubsonicResponseBody

    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

/// The response body with every payload the client asks for. Only the key
/// matching the called endpoint is present; the rest decode as `nil`.
struct SubsonicResponseBody: Decodable {
    let status: String
    let error: SubsonicError?
    let searchResult3: SubsonicSearchResult3?
    let song: SubsonicSong?
    let album: SubsonicAlbum?
    let artist: SubsonicArtist?
    let artists: SubsonicArtistIndexes?
    let playlists: SubsonicPlaylistList?
    let playlist: SubsonicPlaylist?
    let albumList2: SubsonicAlbumList?
    let topSongs: SubsonicSongList?
    let scanStatus: SubsonicScanStatus?

    var isOK: Bool { status == "ok" }
}

public struct SubsonicError: Decodable, Sendable {
    public let code: Int
    public let message: String?
}

public struct SubsonicSearchResult3: Decodable, Sendable {
    public let artist: [SubsonicArtist]?
    public let album: [SubsonicAlbum]?
    public let song: [SubsonicSong]?
}

struct SubsonicArtistIndexes: Decodable {
    let index: [SubsonicArtistIndex]?
}

struct SubsonicArtistIndex: Decodable {
    let name: String?
    let artist: [SubsonicArtist]?
}

struct SubsonicPlaylistList: Decodable {
    let playlist: [SubsonicPlaylist]?
}

struct SubsonicAlbumList: Decodable {
    let album: [SubsonicAlbum]?
}

struct SubsonicSongList: Decodable {
    let song: [SubsonicSong]?
}

/// `getScanStatus`. `count` is how many songs the server has indexed, which
/// is the only place the API reports a library total.
struct SubsonicScanStatus: Decodable {
    let scanning: Bool?
    let count: Int?
}
