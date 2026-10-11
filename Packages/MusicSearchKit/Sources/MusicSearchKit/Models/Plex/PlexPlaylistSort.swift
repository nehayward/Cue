import Foundation

/// How the list of Plex playlists is ordered. Every case is a `sort` field
/// Plex's `/playlists` takes — the orders Plex's own apps offer for it — so
/// the server does the ordering, and the list arrives already in it.
public enum PlexPlaylistSort: String, CaseIterable, Sendable, Identifiable {
    case title
    case dateAdded
    case lastPlayed
    case playCount
    case duration
    case songCount

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .title: "Title"
        case .dateAdded: "Date Added"
        case .lastPlayed: "Last Played"
        case .playCount: "Play Count"
        case .duration: "Duration"
        case .songCount: "Song Count"
        }
    }

    /// Plex's sort field.
    private var field: String {
        switch self {
        case .title: "titleSort"
        case .dateAdded: "addedAt"
        case .lastPlayed: "lastViewedAt"
        case .playCount: "viewCount"
        case .duration: "duration"
        case .songCount: "leafCount"
        }
    }

    /// The direction this order reads best in first — newest, most played
    /// and biggest first, but A–Z for the name.
    public var naturallyDescending: Bool { self != .title }

    /// What the two directions are called, the natural one first. Naming the
    /// ends of the range says what you get where "ascending" wouldn't.
    public var ascendingLabel: String {
        switch self {
        case .title: "A – Z"
        case .dateAdded, .lastPlayed: "Newest First"
        case .playCount: "Most Played"
        case .duration: "Longest First"
        case .songCount: "Most Songs"
        }
    }

    public var descendingLabel: String {
        switch self {
        case .title: "Z – A"
        case .dateAdded, .lastPlayed: "Oldest First"
        case .playCount: "Least Played"
        case .duration: "Shortest First"
        case .songCount: "Fewest Songs"
        }
    }

    /// The `sort` query value. `reversed` flips the natural direction, so
    /// the flag means the same thing here as on the album and song orders.
    /// Every order but Title carries a title tiebreak, so playlists that
    /// were never played, or hold as many songs, come out A–Z.
    public func queryValue(reversed: Bool) -> String {
        let direction = naturallyDescending != reversed ? "desc" : "asc"
        switch self {
        case .title: return "titleSort:\(direction)"
        default: return "\(field):\(direction),titleSort:asc"
        }
    }
}
