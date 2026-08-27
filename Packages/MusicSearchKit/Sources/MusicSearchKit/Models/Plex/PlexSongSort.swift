import Foundation

/// How a list of Plex songs is ordered.
///
/// Unlike Subsonic, Plex sorts on the server: each case is a field for the
/// `sort` parameter on `/library/sections/<id>/all`. Nothing is held locally,
/// so ordering — reversed included — stays correct across a paginated list.
public enum PlexSongSort: String, CaseIterable, Sendable, Identifiable {
    case title
    case artist
    case album
    case year
    case dateAdded
    case playCount
    case lastPlayed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .year: "Year"
        case .dateAdded: "Date Added"
        case .playCount: "Play Count"
        case .lastPlayed: "Last Played"
        }
    }

    /// Plex's sort field.
    private var field: String {
        switch self {
        case .title: "titleSort"
        case .artist: "artist.titleSort"
        case .album: "album.titleSort"
        case .year: "year"
        case .dateAdded: "addedAt"
        case .playCount: "viewCount"
        case .lastPlayed: "lastViewedAt"
        }
    }

    /// The direction this order reads best in first — newest and most-played
    /// first, but A–Z for anything named.
    private var naturallyDescending: Bool {
        switch self {
        case .title, .artist, .album: false
        case .year, .dateAdded, .playCount, .lastPlayed: true
        }
    }

    /// What the two directions are called. "Ascending" says nothing next to
    /// Play Count; naming the ends of the range says what you get.
    public var ascendingLabel: String {
        switch self {
        case .title, .artist, .album: "A – Z"
        case .year, .dateAdded, .lastPlayed: "Newest First"
        case .playCount: "Most Played"
        }
    }

    public var descendingLabel: String {
        switch self {
        case .title, .artist, .album: "Z – A"
        case .year, .dateAdded, .lastPlayed: "Oldest First"
        case .playCount: "Least Played"
        }
    }

    /// The `sort` query value. `reversed` flips the natural direction, so the
    /// flag means the same thing here as it does for a locally sorted list.
    public func queryValue(reversed: Bool) -> String {
        "\(field):\(naturallyDescending != reversed ? "desc" : "asc")"
    }
}
