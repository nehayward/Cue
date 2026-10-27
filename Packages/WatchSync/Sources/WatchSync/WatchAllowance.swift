import Foundation

/// The free tier's share of downloads on the watch, as the iPhone sets it.
///
/// Without Cue Super the free songs are shared between the iPhone and the
/// watch, and books go on neither. Only the iPhone knows about Super, so it
/// tells the watch how many songs it may keep — the free songs the iPhone
/// doesn't hold itself — and whether books may come down; the watch tells
/// the iPhone what it holds (`WatchHeldDownloads`), which the iPhone counts
/// against its own share in turn.
///
/// Nothing on the watch is deleted for it: what's there, or on its way,
/// stays. What's picked beyond the share waits, picked, until there's room
/// or Super.
public struct WatchAllowance: Codable, Equatable, Sendable {
    /// Songs the watch may keep, books' files left out; nil for no limit.
    public var songs: Int?
    public var allowsBooks: Bool

    public init(songs: Int?, allowsBooks: Bool) {
        self.songs = songs
        self.allowsBooks = allowsBooks
    }

    /// Super's, and an iPhone a version behind's, which sends none: a share
    /// that never came holds nothing back.
    public static let unlimited = WatchAllowance(songs: nil, allowsBooks: true)

    /// Which of the songs wanted may be in the watch's downloads, given in
    /// the order they're wanted: those it keeps anyway (`kept`: a file here,
    /// or one on its way), then as many more as the share leaves, in order.
    /// Books' files (`bookFiles`) only when books may come down, and never
    /// from the songs' share.
    public func admitted(_ wanted: [String], kept: Set<String>, bookFiles: Set<String>) -> Set<String> {
        var seen = Set<String>()
        let ordered = wanted.filter { seen.insert($0).inserted }
        var room = songs.map { limit in
            limit - ordered.filter { kept.contains($0) && !bookFiles.contains($0) }.count
        }
        var admitted = Set<String>()
        for key in ordered {
            if kept.contains(key) {
                admitted.insert(key)
            } else if bookFiles.contains(key) {
                if allowsBooks { admitted.insert(key) }
            } else if let left = room {
                guard left > 0 else { continue }
                admitted.insert(key)
                room = left - 1
            } else {
                admitted.insert(key)
            }
        }
        return admitted
    }
}

/// What the watch holds against the free songs: its songs, on the watch or
/// on their way, and its books, one each however many files — as the
/// iPhone counts its own.
public struct WatchHeldDownloads: Codable, Equatable, Sendable {
    public var songs: Int
    public var books: Int

    public init(songs: Int, books: Int) {
        self.songs = songs
        self.books = books
    }

    public var total: Int { songs + books }
}
