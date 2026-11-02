import Foundation

/// How the songs of a playlist are listed. Plex keeps a playlist in the
/// order its songs were added or arranged in and won't sort a playlist's
/// items itself, so every order but the playlist's own is put together
/// here, from the songs once they have all loaded.
public enum PlaylistSongSort: String, CaseIterable, Sendable, Identifiable {
    case playlistOrder
    case title
    case artist
    case album
    case duration

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .playlistOrder: "Playlist Order"
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .duration: "Duration"
        }
    }

    /// The playlist's own order is the one that can be edited and moved
    /// about, so it isn't flipped.
    public var isReversible: Bool { self != .playlistOrder }

    /// The direction this order reads best in first — longest first, but
    /// A–Z for anything named.
    public var naturallyDescending: Bool { self == .duration }

    /// What the two directions are called, the natural one first.
    public var ascendingLabel: String {
        switch self {
        case .playlistOrder, .title, .artist, .album: "A – Z"
        case .duration: "Longest First"
        }
    }

    public var descendingLabel: String {
        switch self {
        case .playlistOrder, .title, .artist, .album: "Z – A"
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
        }
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
