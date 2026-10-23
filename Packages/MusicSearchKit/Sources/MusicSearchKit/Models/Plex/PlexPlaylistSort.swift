import Foundation

/// How the list of Plex playlists is ordered. Plex's `/playlists` sorts by
/// a playlist's own fields, so the server does the ordering for all but Song
/// Count: a playlist's `leafCount` is counted as the list is answered, not a
/// field Plex sorts on. Every playlist comes in one response carrying its
/// count, so that order is put together here (`sort(_:reversed:)`).
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

    /// Plex's sort field. Song Count's is only what `sort(_:reversed:)`
    /// reads.
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
    /// were never played come out A–Z. Song Count asks only for that A–Z
    /// order, which `sort(_:reversed:)` keeps between playlists of the same
    /// size.
    public func queryValue(reversed: Bool) -> String {
        let direction = naturallyDescending != reversed ? "desc" : "asc"
        switch self {
        case .title: return "titleSort:\(direction)"
        case .songCount: return "titleSort:asc"
        default: return "\(field):\(direction),titleSort:asc"
        }
    }

    /// Orders playlists the server returned for `queryValue(reversed:)`:
    /// Song Count by each one's `leafCount`, keeping the server's A–Z order
    /// between playlists of the same size. The other orders arrive sorted
    /// and pass through as they are.
    public func sort(_ playlists: [PlexUserPlaylist], reversed: Bool = false) -> [PlexUserPlaylist] {
        guard self == .songCount else { return playlists }
        let biggestFirst = naturallyDescending != reversed
        return playlists.enumerated().sorted { lhs, rhs in
            let left = lhs.element.leafCount ?? 0, right = rhs.element.leafCount ?? 0
            if left != right { return biggestFirst ? left > right : left < right }
            return lhs.offset < rhs.offset
        }
        .map { $0.element }
    }
}
