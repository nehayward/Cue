import Foundation

/// Something in a music service that Cue's own library points at: a song in
/// a Cue playlist, or an album, playlist, artist or station that's pinned.
/// It's written so any of the person's devices can find the thing again:
/// the service's own id, the server it's on, and what to show while it's
/// looked up.
///
/// It never holds a sign-in. Plex and Subsonic URLs carry their tokens, so
/// artwork on those servers is kept as a path (`serverPath(of:)`) and the
/// app adds the current server and token when it draws it. The stream is
/// built from the current sign-in when the song plays.
public struct CueItem: Codable, Hashable, Sendable {
    /// A service, by name. It's open-ended rather than an enum, so a
    /// playlist that a newer build filled with a service this one hasn't
    /// heard of keeps those songs through a merge instead of dropping them.
    public struct Source: RawRepresentable, Codable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let apple = Source(rawValue: "apple")
        public static let plex = Source(rawValue: "plex")
        public static let subsonic = Source(rawValue: "subsonic")
        public static let files = Source(rawValue: "files")
        public static let tuneIn = Source(rawValue: "tuneIn")
        /// Cue's own: a Cue playlist, when it's pinned.
        public static let cue = Source(rawValue: "cue")
    }

    /// What it is, open-ended for the same reason as `Source`.
    public struct Kind: RawRepresentable, Codable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let song = Kind(rawValue: "song")
        public static let album = Kind(rawValue: "album")
        public static let playlist = Kind(rawValue: "playlist")
        public static let artist = Kind(rawValue: "artist")
        public static let station = Kind(rawValue: "station")
    }

    public var source: Source
    public var kind: Kind
    /// The id Cue's library gives it (`MediaContent.id`): an Apple Music
    /// catalog or library id, a Plex item's id (its server's machine id is
    /// part of it), a Subsonic id, a Files song's hash.
    public var id: String
    /// The server or account it belongs to, where the id alone doesn't say:
    /// a Subsonic server as `user@host`, never with the password, or the
    /// Files folder's name. `nil` where the id is enough.
    public var server: String?
    public var title: String
    /// The artist, or whatever the row shows under the title.
    public var subtitle: String?
    public var album: String?
    public var duration: TimeInterval?
    /// Finds the same recording on another service.
    public var isrc: String?
    /// A full URL where the artwork is public (Apple Music, TuneIn), a path
    /// on the server otherwise.
    public var artwork: String?
    /// Whatever else the app needs to rebuild the item exactly: a
    /// service's own fields, such as the catalog id of an Apple Music
    /// library song. It's open-ended so a newer build's fields survive an
    /// older one.
    public var extras: [String: String]

    public init(
        source: Source,
        kind: Kind,
        id: String,
        server: String? = nil,
        title: String,
        subtitle: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil,
        isrc: String? = nil,
        artwork: String? = nil,
        extras: [String: String] = [:]
    ) {
        self.source = source
        self.kind = kind
        self.id = id
        self.server = server
        self.title = title
        self.subtitle = subtitle
        self.album = album
        self.duration = duration
        self.isrc = isrc
        self.artwork = artwork
        self.extras = extras
    }

    /// The same for one thing wherever it's made, whatever it's called:
    /// what makes a pin a pin, and what a playlist checks to say a song is
    /// already in it.
    public var key: String {
        [kind.rawValue, source.rawValue, server ?? "", id].joined(separator: "|")
    }

    /// Whether `other` is the same thing: the same `key`, without building
    /// two strings to find out.
    public func isSame(as other: CueItem) -> Bool {
        id == other.id && source == other.source && kind == other.kind && server == other.server
    }

    private enum CodingKeys: String, CodingKey {
        case source, kind, id, server, title, subtitle, album, duration, isrc, artwork, extras
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(Source.self, forKey: .source)
        kind = try container.decode(Kind.self, forKey: .kind)
        id = try container.decode(String.self, forKey: .id)
        server = try container.decodeIfPresent(String.self, forKey: .server)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        album = try container.decodeIfPresent(String.self, forKey: .album)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        isrc = try container.decodeIfPresent(String.self, forKey: .isrc)
        artwork = try container.decodeIfPresent(String.self, forKey: .artwork)
        extras = try container.decodeIfPresent([String: String].self, forKey: .extras) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(kind, forKey: .kind)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(server, forKey: .server)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(album, forKey: .album)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(isrc, forKey: .isrc)
        try container.encodeIfPresent(artwork, forKey: .artwork)
        if !extras.isEmpty {
            try container.encode(extras, forKey: .extras)
        }
    }
}

// MARK: - Keeping sign-ins out

extension CueItem {
    /// The query items that sign a request to a server: Plex's token and
    /// client fields, and Subsonic's user, token, salt, password, client,
    /// version and format. They belong to one device's sign-in and never go
    /// into a synced record. Compared without case.
    public static let signingQueryItems: Set<String> = [
        "x-plex-token", "x-plex-client-identifier", "x-plex-product", "x-plex-version",
        "x-plex-platform", "x-plex-platform-version", "x-plex-device", "x-plex-device-name",
        "x-plex-session-identifier", "x-plex-language",
        "u", "t", "s", "p", "c", "v", "f", "apikey", "token", "access_token",
    ]

    /// `url`'s path and query without its scheme, host or signing items:
    /// what to keep of a Plex or Subsonic artwork URL. The host and the
    /// token belong to the sign-in it was made with, and the app adds the
    /// current ones back when it draws the artwork.
    public static func serverPath(of url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = nil
        components.user = nil
        components.password = nil
        components.host = nil
        components.port = nil
        components.fragment = nil
        removeSigningItems(from: &components)
        return components.string
    }

    /// `url` without its signing items, for artwork that's public anyway.
    public static func unsigned(_ url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.user = nil
        components.password = nil
        removeSigningItems(from: &components)
        return components.string
    }

    /// Whether `string` still carries anything that signs a request: the
    /// check a record goes through before it's sent.
    public static func carriesSignIn(_ string: String) -> Bool {
        guard let components = URLComponents(string: string) else { return false }
        if components.password != nil { return true }
        return (components.percentEncodedQueryItems ?? []).contains {
            signingQueryItems.contains($0.name.lowercased())
        }
    }

    private static func removeSigningItems(from components: inout URLComponents) {
        guard let items = components.percentEncodedQueryItems else { return }
        let kept = items.filter { !signingQueryItems.contains($0.name.lowercased()) }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
    }
}
