import Foundation

/// A playlist or album someone shared, read out of whatever they pasted: a
/// link on its own, a link inside a sentence ("Check out this playlist
/// https://…"), a `spotify:` URI, or a list of Spotify song links (what
/// Spotify's desktop app copies from a selection).
public enum PlaylistLink: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case playlist
        case album
    }

    case spotify(Kind, id: String)
    /// Songs picked one by one, in order.
    case spotifyTracks([String])
    /// `spotify.link/…`: where it goes is only known by following it.
    case spotifyShortLink(URL)
    case appleMusic(Kind, id: String, storefront: String?)
    /// A playlist in someone's own library (`p.…`), which only they can read.
    case appleMusicLibrary(id: String)

    public init?(_ text: String) {
        let tokens = text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'()[],")) }
            .filter { !$0.isEmpty }

        // A list of song links is a playlist of its own.
        let songs = tokens.compactMap(Self.spotifyTrackID)
        if songs.count > 1 {
            self = .spotifyTracks(songs)
            return
        }

        for token in tokens {
            if let link = Self.parse(token) {
                self = link
                return
            }
        }
        if let id = songs.first {
            self = .spotifyTracks([id])
            return
        }
        return nil
    }

    public var serviceTitle: String {
        switch self {
        case .spotify, .spotifyTracks, .spotifyShortLink: "Spotify"
        case .appleMusic, .appleMusicLibrary: "Apple Music"
        }
    }

    private static func parse(_ token: String) -> PlaylistLink? {
        if token.lowercased().hasPrefix("spotify:") {
            return spotifyURI(token)
        }
        guard let url = URL(string: token), let host = url.host?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "open.spotify.com", "play.spotify.com":
            return spotifyPath(path)
        case "spotify.link", "spotify.app.link":
            return .spotifyShortLink(url)
        case "music.apple.com", "embed.music.apple.com", "itunes.apple.com", "geo.music.apple.com":
            return appleMusicPath(path)
        default:
            return nil
        }
    }

    /// `spotify:playlist:ID`, `spotify:album:ID`, and the older
    /// `spotify:user:NAME:playlist:ID`.
    private static func spotifyURI(_ uri: String) -> PlaylistLink? {
        let parts = uri.split(separator: ":").map(String.init)
        for (index, part) in parts.enumerated() where index + 1 < parts.count {
            if let kind = Kind(rawValue: part.lowercased()) {
                return .spotify(kind, id: parts[index + 1])
            }
        }
        return nil
    }

    /// `/playlist/ID`, with or without `/intl-de`, `/embed` or `/user/NAME`
    /// in front of it.
    private static func spotifyPath(_ path: [String]) -> PlaylistLink? {
        for (index, part) in path.enumerated() where index + 1 < path.count {
            if let kind = Kind(rawValue: part.lowercased()), isSpotifyID(path[index + 1]) {
                return .spotify(kind, id: path[index + 1])
            }
        }
        return nil
    }

    private static func spotifyTrackID(_ token: String) -> String? {
        if token.lowercased().hasPrefix("spotify:track:") {
            let id = String(token.dropFirst("spotify:track:".count))
            return isSpotifyID(id) ? id : nil
        }
        guard let url = URL(string: token), url.host?.lowercased() == "open.spotify.com" else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        guard let index = path.firstIndex(of: "track"), index + 1 < path.count, isSpotifyID(path[index + 1]) else { return nil }
        return path[index + 1]
    }

    /// Spotify ids are 22 characters of base 62.
    private static func isSpotifyID(_ id: String) -> Bool {
        id.count == 22 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// `/us/playlist/name/pl.…`, `/us/album/name/123`, `/library/playlist/p.…`.
    private static func appleMusicPath(_ path: [String]) -> PlaylistLink? {
        let storefront = path.first.flatMap { $0.count == 2 ? $0.lowercased() : nil }
        if let index = path.firstIndex(of: "playlist"), let id = path[(index + 1)...].last {
            if id.hasPrefix("pl.") { return .appleMusic(.playlist, id: id, storefront: storefront) }
            if id.hasPrefix("p.") { return .appleMusicLibrary(id: id) }
            return nil
        }
        if let index = path.firstIndex(of: "album"), let id = path[(index + 1)...].last,
           !id.isEmpty, id.allSatisfy(\.isNumber) {
            return .appleMusic(.album, id: id, storefront: storefront)
        }
        return nil
    }
}

/// Why a playlist couldn't be imported, in words for the person importing it.
public enum PlaylistImportError: LocalizedError, Equatable, Sendable {
    /// Nothing answered, or what answered couldn't be read.
    case unreachable
    /// The link leads nowhere: deleted, private, or mistyped.
    case notFound
    case empty
    case unsupported
    /// Apple Music access is off for Cue.
    case appleMusicNotAuthorized

    public var errorDescription: String? {
        switch self {
        case .unreachable:
            "The playlist couldn’t be loaded. Check your connection and try again."
        case .notFound:
            "That playlist couldn’t be found. It may be private or deleted."
        case .empty:
            "That playlist has no songs."
        case .unsupported:
            "That isn’t a Spotify or Apple Music playlist or album link."
        case .appleMusicNotAuthorized:
            "Cue needs access to Apple Music to read this. Turn it on in Settings ▸ Cue ▸ Media & Apple Music."
        }
    }
}
