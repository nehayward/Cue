import Foundation

/// How a list of Plex songs is ordered.
///
/// Plex can sort either way. The `sort` query field below is what a
/// paginated request uses; `sort(_:reversed:)` is the same order applied to
/// the synced copy of the library, which is how the Songs list gets it
/// without going back to the server.
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

    /// Orders songs in memory, matching what the server would return for the
    /// same case.
    public func sort(_ songs: [PlexMetadata], reversed: Bool = false) -> [PlexMetadata] {
        let ordered: [PlexMetadata]
        switch self {
        case .title:
            ordered = songs.sorted { compare($0.title, $1.title) ?? (compare($0.grandparentTitle, $1.grandparentTitle) ?? false) }
        case .artist:
            // Artist, then their albums, then each album's running order —
            // the same shape as opening the artist.
            ordered = songs.sorted {
                compare($0.grandparentTitle, $1.grandparentTitle)
                    ?? compare($0.parentTitle, $1.parentTitle)
                    ?? (position($0) < position($1))
            }
        case .album:
            ordered = songs.sorted { compare($0.parentTitle, $1.parentTitle) ?? (position($0) < position($1)) }
        case .year:
            ordered = songs.sorted {
                descending($0.year ?? $0.parentYear, $1.year ?? $1.parentYear)
                    ?? compare($0.parentTitle, $1.parentTitle)
                    ?? (position($0) < position($1))
            }
        case .dateAdded:
            ordered = songs.sorted { descending($0.addedAt, $1.addedAt) ?? (compare($0.title, $1.title) ?? false) }
        case .playCount:
            ordered = songs.sorted { descending($0.viewCount, $1.viewCount) ?? (compare($0.title, $1.title) ?? false) }
        case .lastPlayed:
            ordered = songs.sorted { descending($0.lastViewedAt, $1.lastViewedAt) ?? (compare($0.title, $1.title) ?? false) }
        }
        return reversed ? ordered.reversed() : ordered
    }
}

/// Ascending text comparison, `nil` when the two are equal so callers can
/// chain a tiebreak with `??`.
private func compare(_ lhs: String?, _ rhs: String?) -> Bool? {
    switch (lhs ?? "").localizedStandardCompare(rhs ?? "") {
    case .orderedAscending: true
    case .orderedDescending: false
    case .orderedSame: nil
    }
}

/// Descending number comparison; missing values sort last.
private func descending(_ lhs: Int?, _ rhs: Int?) -> Bool? {
    let left = lhs ?? .min, right = rhs ?? .min
    return left == right ? nil : left > right
}

/// A song's place within its album: disc, then track.
private func position(_ song: PlexMetadata) -> (Int, Int) {
    (song.parentIndex ?? 1, song.index ?? 0)
}
