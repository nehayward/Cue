import Foundation

// Browsing the iPhone's libraries from the watch. The watch asks with a
// `WatchRequest` (`sendMessageData`, which wakes Cue on the iPhone if it
// isn't running) and the iPhone answers with a `WatchReply`: a page of its
// Plex or Subsonic library, or the outcome of putting something on the
// watch. The iPhone does the fetching with its own accounts, and adding goes
// through the same library and sync as Add to Apple Watch on the iPhone.

/// A library on the iPhone the watch can browse.
public enum WatchSource: String, Codable, CaseIterable, Hashable, Sendable {
    case plex, subsonic

    public var title: String {
        switch self {
        case .plex: "Plex"
        case .subsonic: "Subsonic"
        }
    }
}

/// The lists a library offers.
public enum WatchBrowseSection: String, Codable, CaseIterable, Hashable, Sendable {
    case playlists, albums, artists, recentlyAdded

    public var title: String {
        switch self {
        case .playlists: "Playlists"
        case .albums: "Albums"
        case .artists: "Artists"
        case .recentlyAdded: "Recently Added"
        }
    }

    public var symbol: String {
        switch self {
        case .playlists: "music.note.list"
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .recentlyAdded: "clock"
        }
    }
}

/// Enough of an album, playlist or artist for the iPhone to find it again.
public struct WatchContentRef: Codable, Hashable, Sendable {
    public let source: WatchSource
    public let kind: WatchCollection.Kind
    public let id: String
    public let title: String
    public let subtitle: String
    public let artworkURL: URL?

    public init(source: WatchSource, kind: WatchCollection.Kind, id: String, title: String, subtitle: String, artworkURL: URL?) {
        self.source = source
        self.kind = kind
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
    }
}

/// Where in the iPhone's libraries a page comes from.
public enum WatchBrowsePath: Codable, Hashable, Sendable {
    /// The libraries the iPhone has set up.
    case root
    /// One library's lists.
    case source(WatchSource)
    case section(WatchSource, WatchBrowseSection)
    /// An artist's albums.
    case artist(WatchContentRef)
}

/// A row: a place to go, music that can go on the watch, or both (an
/// artist on Subsonic, which goes whole).
public struct WatchBrowseItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let artworkURL: URL?
    /// An SF Symbol, for a row that's a place rather than music.
    public let symbol: String?
    /// Where tapping it goes, for a place or an artist.
    public let destination: WatchBrowsePath?
    /// The music itself, when it can go on the watch whole.
    public let content: WatchContentRef?
    /// The key its collection has in the watch's library once it's there,
    /// so the watch can tell from its own library whether it is.
    public let collectionKey: String?

    public init(
        id: String,
        title: String,
        subtitle: String = "",
        artworkURL: URL? = nil,
        symbol: String? = nil,
        destination: WatchBrowsePath? = nil,
        content: WatchContentRef? = nil,
        collectionKey: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.symbol = symbol
        self.destination = destination
        self.content = content
        self.collectionKey = collectionKey
    }
}

public struct WatchBrowsePage: Codable, Sendable {
    public let title: String
    public let items: [WatchBrowseItem]
    /// The offset to ask for next, or nil at the end.
    public let nextOffset: Int?
    /// What the page is of, when that can go on the watch whole.
    public let container: WatchBrowseItem?
    /// Said when there's nothing to list (no server set up, say).
    public let message: String?

    public init(title: String, items: [WatchBrowseItem], nextOffset: Int? = nil, container: WatchBrowseItem? = nil, message: String? = nil) {
        self.title = title
        self.items = items
        self.nextOffset = nextOffset
        self.container = container
        self.message = message
    }
}

public enum WatchRequest: Codable, Sendable, Equatable {
    case browse(WatchBrowsePath, offset: Int)
    /// Puts it on the watch, at `quality` if the iPhone has none set yet.
    case add(WatchContentRef, quality: WatchDownloadQuality?)
    case remove(WatchContentRef)

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) throws -> WatchRequest {
        try JSONDecoder().decode(WatchRequest.self, from: data)
    }
}

public enum WatchReply: Codable, Sendable {
    case page(WatchBrowsePage)
    case added(songs: Int)
    case removed
    /// No download quality chosen yet: ask, then send the add again with one.
    case needsQuality
    case failed(String)

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data) throws -> WatchReply {
        try JSONDecoder().decode(WatchReply.self, from: data)
    }

    /// The number of rows a page carries, so a reply stays well inside what
    /// WatchConnectivity will carry (about 64 KB).
    public static let pageSize = 40
}
