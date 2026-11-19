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
    /// What the server calls itself (`navidrome`, `gonic`, …), which
    /// OpenSubsonic servers put in every response. Nil from older servers.
    /// Lenient, as every response is decoded with this: a server sending
    /// something else there must not fail them all.
    private let serverType: LenientString?
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
    let starred2: SubsonicStarred2?
    let lyricsList: SubsonicLyricsList?
    let lyrics: SubsonicLegacyLyrics?

    var isOK: Bool { status == "ok" }
    var type: String? { serverType?.value }

    private enum CodingKeys: String, CodingKey {
        case status, error, searchResult3, song, album, artist, artists, playlists, playlist
        case albumList2, topSongs, scanStatus, starred2, lyricsList, lyrics
        case serverType = "type"
    }
}

/// A string, or nil when the value is anything else.
struct LenientString: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(String.self)
    }
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

/// `getStarred2` — everything the current user has starred, in one response.
/// The endpoint takes no paging parameters: what it returns is the whole list.
struct SubsonicStarred2: Decodable {
    let song: [SubsonicSong]?
    let album: [SubsonicAlbum]?
    let artist: [SubsonicArtist]?
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
