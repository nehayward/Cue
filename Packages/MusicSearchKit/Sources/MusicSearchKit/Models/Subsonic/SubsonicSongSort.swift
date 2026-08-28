import Foundation

/// How a list of Subsonic songs is ordered.
///
/// Sorting is done here rather than by the server because the Subsonic API
/// has no sort parameter for songs — `search3` takes only counts and offsets
/// and leaves the order of its results unspecified. Every client with a
/// sortable Songs list works this way: hold a copy of the library, order it
/// locally.
public enum SubsonicSongSort: String, CaseIterable, Sendable, Identifiable {
    case title
    case artist
    case album
    case year
    case playCount
    case dateAdded
    case favorites

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .year: "Year"
        case .playCount: "Play Count"
        case .dateAdded: "Date Added"
        case .favorites: "Favorites"
        }
    }

    /// Favorites has no meaningful opposite — "least favorite first" is just
    /// the rest of the library — so it offers no direction toggle.
    public var isReversible: Bool { self != .favorites }

    /// What the two directions are called for this order. "Ascending" and
    /// "Descending" mean nothing next to Play Count; naming the ends of the
    /// range says what you actually get.
    public var ascendingLabel: String {
        switch self {
        case .title, .artist, .album: "A – Z"
        case .year, .dateAdded: "Newest First"
        case .playCount: "Most Played"
        case .favorites: "Favorites First"
        }
    }

    public var descendingLabel: String {
        switch self {
        case .title, .artist, .album: "Z – A"
        case .year, .dateAdded: "Oldest First"
        case .playCount: "Least Played"
        case .favorites: "Favorites Last"
        }
    }

    /// Orders songs for this mode. The text sorts read alphabetically; the
    /// numeric ones (year, play count, date added) read most/newest first,
    /// which is the only reading those columns are asked for.
    public func sort(_ songs: [SubsonicSong]) -> [SubsonicSong] {
        switch self {
        case .title:
            songs.sorted { compare($0.title, $1.title) ?? (compare($0.artist, $1.artist) ?? false) }
        case .artist:
            // Artist, then their albums, then each album's own running order —
            // the same shape as opening the artist, which is what makes an
            // artist sort useful rather than just grouped.
            songs.sorted {
                compare($0.artist, $1.artist)
                    ?? compare($0.album, $1.album)
                    ?? (position($0) < position($1))
            }
        case .album:
            songs.sorted { compare($0.album, $1.album) ?? (position($0) < position($1)) }
        case .year:
            songs.sorted {
                descending($0.year, $1.year)
                    ?? compare($0.album, $1.album)
                    ?? (position($0) < position($1))
            }
        case .playCount:
            songs.sorted { descending($0.playCount, $1.playCount) ?? (compare($0.title, $1.title) ?? false) }
        case .dateAdded:
            // ISO 8601 timestamps compare correctly as text, so there is no
            // reason to parse thousands of them into dates just to sort.
            songs.sorted {
                descendingText($0.created, $1.created) ?? (compare($0.title, $1.title) ?? false)
            }
        case .favorites:
            // Starred first, most recently starred at the top — `starred` is
            // the date it happened. The rest of the library keeps title order
            // underneath rather than being hidden: this is a sort, not a
            // filter, and the count under the title stays honest.
            songs.sorted { lhs, rhs in
                let left = lhs.starred ?? "", right = rhs.starred ?? ""
                if left.isEmpty != right.isEmpty { return !left.isEmpty }
                if !left.isEmpty { return left > right }
                return compare(lhs.title, rhs.title) ?? false
            }
        }
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

/// Descending text comparison; missing values sort last.
private func descendingText(_ lhs: String?, _ rhs: String?) -> Bool? {
    let left = lhs ?? "", right = rhs ?? ""
    return left == right ? nil : left > right
}

/// A song's place within its album.
private func position(_ song: SubsonicSong) -> (Int, Int) {
    (song.discNumber ?? 1, song.track ?? 0)
}
