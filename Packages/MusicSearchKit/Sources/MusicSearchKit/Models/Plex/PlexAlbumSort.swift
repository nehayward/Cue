import Foundation

/// How a list of Plex albums is ordered. Every case is a Plex `sort` field,
/// so the server does the ordering and each page arrives already in it —
/// reversing works on the whole library, not the page in front of you.
public enum PlexAlbumSort: String, CaseIterable, Sendable, Identifiable {
    case title
    case artist
    case year
    case recentlyAdded

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .year: "Year"
        case .recentlyAdded: "Recently Added"
        }
    }

    /// The direction this order reads best in first — newest first for a
    /// date, A–Z for anything named.
    public var naturallyDescending: Bool {
        switch self {
        case .title, .artist: false
        case .year, .recentlyAdded: true
        }
    }

    public var ascendingLabel: String {
        switch self {
        case .title, .artist: "A – Z"
        case .year, .recentlyAdded: "Newest First"
        }
    }

    public var descendingLabel: String {
        switch self {
        case .title, .artist: "Z – A"
        case .year, .recentlyAdded: "Oldest First"
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
        case .artist: return "artist.titleSort:\(direction),titleSort:asc"
        case .year: return "year:\(direction),titleSort:asc"
        case .recentlyAdded: return "addedAt:\(direction),titleSort:asc"
        }
    }
}
