import Foundation

/// How a list of Plex albums, or artists, is ordered. Every case is a Plex
/// `sort` field, so the server does the ordering and each page arrives
/// already in it — reversing works on the whole library, not the page in
/// front of you.
public enum PlexAlbumSort: String, CaseIterable, Sendable, Identifiable {
    case title
    case artist
    case year
    case recentlyAdded
    case playCount
    case lastPlayed
    case favorites

    public var id: String { rawValue }

    /// The orders an artist has: its own fields, with no artist or year.
    public static let artistSorts: [PlexAlbumSort] = [.title, .recentlyAdded, .playCount, .lastPlayed, .favorites]

    public var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .year: "Year"
        case .recentlyAdded: "Recently Added"
        case .playCount: "Play Count"
        case .lastPlayed: "Last Played"
        case .favorites: "Favorites"
        }
    }

    /// Favorites has no meaningful opposite — "least favorite first" is
    /// just the rest of the library — so it offers no direction toggle, as
    /// on Songs.
    public var isReversible: Bool { self != .favorites }

    /// The direction this order reads best in first — newest and
    /// most-played first, A–Z for anything named.
    public var naturallyDescending: Bool {
        switch self {
        case .title, .artist: false
        case .year, .recentlyAdded, .playCount, .lastPlayed, .favorites: true
        }
    }

    public var ascendingLabel: String {
        switch self {
        case .title, .artist: "A – Z"
        case .year, .recentlyAdded, .lastPlayed: "Newest First"
        case .playCount: "Most Played"
        case .favorites: "Favorites First"
        }
    }

    public var descendingLabel: String {
        switch self {
        case .title, .artist: "Z – A"
        case .year, .recentlyAdded, .lastPlayed: "Oldest First"
        case .playCount: "Least Played"
        case .favorites: "Favorites Last"
        }
    }

    /// Plex's sort field. Favorites is a rating above zero, the same test
    /// FavoriteMenuButton makes: Plex has no favorite flag of its own.
    private var field: String {
        switch self {
        case .title: "titleSort"
        case .artist: "artist.titleSort"
        case .year: "year"
        case .recentlyAdded: "addedAt"
        case .playCount: "viewCount"
        case .lastPlayed: "lastViewedAt"
        case .favorites: "userRating"
        }
    }

    /// The `sort` query value. `reversed` flips the natural direction, so
    /// the flag means the same thing here as on a locally sorted list. Every
    /// order but Title carries a title tiebreak, so an artist's albums — or
    /// a year's — come out A–Z rather than in whatever order the server
    /// keeps them.
    public func queryValue(reversed: Bool) -> String {
        let direction = naturallyDescending != reversed ? "desc" : "asc"
        switch self {
        case .title: return "titleSort:\(direction)"
        default: return "\(field):\(direction),titleSort:asc"
        }
    }
}
