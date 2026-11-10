import Foundation

/// How the songs of a playlist are listed. A playlist is kept in the order
/// its songs were added or arranged in, and Plex won't sort a playlist's
/// items itself, so every order but the playlist's own is put together
/// here, from the songs once they have all loaded. Listing them in another
/// order never changes the playlist.
public enum PlaylistSongSort: String, CaseIterable, Sendable, Identifiable {
    case playlistOrder
    case title
    case artist
    case album
    case dateAdded
    case lastPlayed
    case playCount
    case rating
    case duration

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .playlistOrder: "Playlist Order"
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .dateAdded: "Date Added"
        case .lastPlayed: "Last Played"
        case .playCount: "Play Count"
        case .rating: "Rating"
        case .duration: "Duration"
        }
    }

    /// Orders that read what only a library server tells about a song
    /// (Plex): when it came into the library, its plays and its rating.
    public var readsLibraryDetails: Bool {
        switch self {
        case .dateAdded, .lastPlayed, .playCount, .rating: true
        case .playlistOrder, .title, .artist, .album, .duration: false
        }
    }

    /// The orders a playlist's songs can be listed in: the ones that read
    /// library details only where its songs carry them.
    public static func options(withLibraryDetails: Bool) -> [PlaylistSongSort] {
        allCases.filter { withLibraryDetails || !$0.readsLibraryDetails }
    }

    /// The playlist's own order is the one that can be edited and moved
    /// about, so it isn't flipped.
    public var isReversible: Bool { self != .playlistOrder }

    /// The direction this order reads best in first — newest, most played,
    /// best rated and longest first, but A–Z for anything named.
    public var naturallyDescending: Bool {
        switch self {
        case .dateAdded, .lastPlayed, .playCount, .rating, .duration: true
        case .playlistOrder, .title, .artist, .album: false
        }
    }

    /// What the two directions are called, the natural one first.
    public var ascendingLabel: String {
        switch self {
        case .playlistOrder, .title, .artist, .album: "A – Z"
        case .dateAdded, .lastPlayed: "Newest First"
        case .playCount: "Most Played"
        case .rating: "Highest First"
        case .duration: "Longest First"
        }
    }

    public var descendingLabel: String {
        switch self {
        case .playlistOrder, .title, .artist, .album: "Z – A"
        case .dateAdded, .lastPlayed: "Oldest First"
        case .playCount: "Least Played"
        case .rating: "Lowest First"
        case .duration: "Shortest First"
        }
    }

    /// The indices of `songs` in this order. Songs that tie keep their
    /// playlist order, and a song missing what the order reads (no artist,
    /// no length) goes last either way round. `reversed` flips the natural
    /// direction.
    public func order(of songs: [PlayableContent], reversed: Bool = false) -> [Int] {
        guard self != .playlistOrder else { return Array(songs.indices) }
        let descending = naturallyDescending != reversed
        return songs.indices.sorted { lhs, rhs in
            switch compare(songs[lhs], songs[rhs], descending: descending) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs < rhs
            }
        }
    }

    private func compare(_ lhs: PlayableContent, _ rhs: PlayableContent, descending: Bool) -> ComparisonResult {
        switch self {
        case .playlistOrder:
            return .orderedSame
        case .title:
            return Self.text(lhs.title, rhs.title, descending: descending)
        case .artist:
            // An artist's songs together, album by album.
            return Self.text(lhs.metadata?.artist, rhs.metadata?.artist, descending: descending)
                .then(Self.text(lhs.metadata?.album, rhs.metadata?.album, descending: false))
        case .album:
            return Self.text(lhs.metadata?.album, rhs.metadata?.album, descending: descending)
        case .duration:
            return Self.ranked(lhs.metadata?.duration, rhs.metadata?.duration, descending: descending)
                .then(Self.text(lhs.title, rhs.title, descending: false))
        case .dateAdded:
            return Self.ranked(lhs.metadata?.addedAt, rhs.metadata?.addedAt, descending: descending)
        case .lastPlayed:
            // A song never played has no date, so it goes last either way.
            return Self.ranked(lhs.metadata?.lastPlayedAt, rhs.metadata?.lastPlayedAt, descending: descending)
        case .playCount:
            return Self.ranked(lhs.metadata?.playCount, rhs.metadata?.playCount, descending: descending)
        case .rating:
            // Plex's 0 is no rating, not the lowest: unrated songs go last.
            return Self.ranked(Self.rating(of: lhs), Self.rating(of: rhs), descending: descending)
        }
    }

    private static func rating(of song: PlayableContent) -> Double? {
        song.metadata?.userRating.flatMap { $0 > 0 ? $0 : nil }
    }

    /// Names in the order Finder uses (numbers by value, case and accents
    /// aside); a missing or empty one last.
    private static func text(_ lhs: String?, _ rhs: String?, descending: Bool) -> ComparisonResult {
        let lhs = lhs?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhs = rhs?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ranked(lhs.flatMap { $0.isEmpty ? nil : $0 }, rhs.flatMap { $0.isEmpty ? nil : $0 }, descending: descending) {
            $0.localizedStandardCompare($1)
        }
    }

    private static func ranked<Value: Comparable>(_ lhs: Value?, _ rhs: Value?, descending: Bool) -> ComparisonResult {
        ranked(lhs, rhs, descending: descending) { lhs, rhs in
            lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
        }
    }

    /// `compare` in the asked direction, with a missing value after any
    /// value whichever the direction.
    private static func ranked<Value>(
        _ lhs: Value?,
        _ rhs: Value?,
        descending: Bool,
        by compare: (Value, Value) -> ComparisonResult
    ) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            let result = compare(lhs, rhs)
            guard descending else { return result }
            switch result {
            case .orderedAscending: return .orderedDescending
            case .orderedDescending: return .orderedAscending
            case .orderedSame: return .orderedSame
            }
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        }
    }
}

private extension ComparisonResult {
    /// `next` breaks a tie.
    func then(_ next: @autoclosure () -> ComparisonResult) -> ComparisonResult {
        self == .orderedSame ? next() : self
    }
}
