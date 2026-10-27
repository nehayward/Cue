import Foundation
import MusicSearchKit
import Observation
import SonosKit

/// The places the listener marked in each book, each with what they called
/// it: a line to come back to, a scene to play someone. Made from the
/// player's menu or the Chapters sheet, listed there and on the book's
/// page, where a tap plays the book from there.
///
/// Audiobookshelf keeps a book's bookmarks too, so for its books each one
/// goes to the server as it's made, renamed or taken away, and the server's
/// are taken in as the shelves load (`merge(fromServer:)`): one made in
/// another of its apps shows here, one taken away there goes here too, and
/// one made or taken away here while the server couldn't be told is told
/// it then. Plex keeps none, nor does an Audiobookshelf podcast's episode:
/// theirs stay on this device. In Application Support, by
/// `AudiobookProgressStore.key`.
@MainActor
@Observable
final class AudiobookBookmarks {
    static let shared = AudiobookBookmarks()

    struct Bookmark: Codable, Hashable, Identifiable {
        var id = UUID()
        /// Book time.
        let position: TimeInterval
        var title: String
        let date: Date
        /// Whether the server has it: false for one it hasn't been told of
        /// yet, nil for a book whose server keeps no bookmarks.
        var onServer: Bool?
        /// The server's id for the book, for one it keeps.
        var serverItemID: String?
    }

    private struct Stored: Codable {
        var bookmarks: [String: [Bookmark]]
        /// Taken away here but not yet on the server, by book: their times.
        var pendingRemovals: [String: [TimeInterval]]
    }

    /// Each book's bookmarks in book order, by `AudiobookProgressStore.key`.
    private(set) var bookmarks: [String: [Bookmark]] = [:]
    @ObservationIgnored private var pendingRemovals: [String: [TimeInterval]] = [:]

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private static let io = DispatchQueue(label: "dance.cue.audiobookBookmarks", qos: .utility)

    /// Two bookmarks closer than this are the same place.
    private static let samePlace: TimeInterval = 1

    private init() {
        if let url = Self.fileURL, let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            bookmarks = stored.bookmarks
            pendingRemovals = stored.pendingRemovals
        }
    }

    func bookmarks(for book: PlayableContent) -> [Bookmark] {
        bookmarks[AudiobookProgressStore.key(for: book)] ?? []
    }

    /// What a bookmark is called until it's renamed: the chapter it's in,
    /// else the time.
    static func defaultTitle(at position: TimeInterval, in audiobook: Audiobook?) -> String {
        if let audiobook, audiobook.chapters.count > 1, let chapter = audiobook.chapter(at: position) {
            return chapter.title
        }
        return "Bookmark at \(AudiobookFormat.clock(position))"
    }

    /// The server's id for `book`, when it keeps the book's bookmarks.
    private static func serverItemID(of book: PlayableContent) -> String? {
        guard book.content.service == .audiobookshelf, !book.isPodcastEpisode else { return nil }
        return book.content.id
    }

    // MARK: - Making, renaming, taking away

    /// Marks `position` in `book`, called `title`, and tells the server. A
    /// place already marked is that bookmark.
    @discardableResult
    func add(at position: TimeInterval, title: String, to book: PlayableContent) -> Bookmark {
        // Whole seconds, as Audiobookshelf's own apps make them, so the
        // server names it by the same time.
        let time = max(position.rounded(.down), 0)
        let key = AudiobookProgressStore.key(for: book)
        var list = bookmarks[key] ?? []
        if let existing = list.first(where: { abs($0.position - time) < Self.samePlace }) {
            return existing
        }
        let itemID = Self.serverItemID(of: book)
        let bookmark = Bookmark(position: time, title: title, date: .now, onServer: itemID == nil ? nil : false, serverItemID: itemID)
        list.append(bookmark)
        bookmarks[key] = list.sorted { $0.position < $1.position }
        pendingRemovals[key]?.removeAll { abs($0 - time) < Self.samePlace }
        scheduleSave()
        if let itemID {
            send(bookmark, itemID: itemID, key: key)
        }
        return bookmark
    }

    func rename(_ bookmark: Bookmark, to title: String, in book: PlayableContent) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = AudiobookProgressStore.key(for: book)
        guard !title.isEmpty, var list = bookmarks[key],
              let index = list.firstIndex(where: { $0.id == bookmark.id }) else { return }
        list[index].title = title
        bookmarks[key] = list
        scheduleSave()
        // One the server hasn't been told of yet goes with its new name.
        guard list[index].onServer == true, let itemID = list[index].serverItemID else { return }
        let time = list[index].position
        Task { await AudiobookshelfAPI.shared.renameBookmark(itemID: itemID, time: time, title: title) }
    }

    func remove(_ bookmark: Bookmark, from book: PlayableContent) {
        let key = AudiobookProgressStore.key(for: book)
        bookmarks[key]?.removeAll { $0.id == bookmark.id }
        if bookmarks[key]?.isEmpty == true {
            bookmarks[key] = nil
        }
        defer { scheduleSave() }
        guard bookmark.onServer == true, let itemID = bookmark.serverItemID else { return }
        // Kept until the server has let it go, so a read of its list before
        // then doesn't bring it back.
        pendingRemovals[key, default: []].append(bookmark.position)
        sendRemoval(at: bookmark.position, itemID: itemID, key: key)
    }

    // MARK: - The server's

    /// Takes in Audiobookshelf's bookmarks, by its book ids
    /// (`AudiobookshelfAPI.account()`): its list is the book's, but for
    /// those made here it hasn't been told of, which go to it now, and
    /// those taken away here it still has, which it's told of again.
    func merge(fromServer server: [String: [AudiobookshelfBookmark]]) {
        var books: [String: String] = [:]
        for itemID in server.keys {
            books[AudiobookProgressStore.key(service: .audiobookshelf, id: itemID)] = itemID
        }
        for (key, list) in bookmarks {
            if let itemID = list.lazy.compactMap(\.serverItemID).first {
                books[key] = itemID
            }
        }
        for (key, itemID) in books {
            let local = bookmarks[key] ?? []
            let removed = pendingRemovals[key] ?? []
            var merged: [Bookmark] = []
            for mark in server[itemID] ?? [] {
                if removed.contains(where: { abs($0 - mark.time) < Self.samePlace }) {
                    sendRemoval(at: mark.time, itemID: itemID, key: key)
                    continue
                }
                guard !merged.contains(where: { abs($0.position - mark.time) < Self.samePlace }) else { continue }
                let title = mark.title.flatMap { $0.isEmpty ? nil : $0 }
                // This device's copy keeps its id, so its row stays put.
                if var mine = local.first(where: { abs($0.position - mark.time) < Self.samePlace }) {
                    mine.title = title ?? mine.title
                    mine.onServer = true
                    mine.serverItemID = itemID
                    merged.append(mine)
                } else {
                    merged.append(Bookmark(
                        position: mark.time,
                        title: title ?? "Bookmark at \(AudiobookFormat.clock(mark.time))",
                        date: mark.createdAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } ?? .now,
                        onServer: true,
                        serverItemID: itemID
                    ))
                }
            }
            // Made here and not on the server yet: kept, and sent now. One
            // the server had and hasn't any more was taken away elsewhere.
            for mine in local where mine.onServer != true
                && !merged.contains(where: { abs($0.position - mine.position) < Self.samePlace }) {
                merged.append(mine)
                if mine.serverItemID != nil {
                    send(mine, itemID: itemID, key: key)
                }
            }
            let sorted = merged.sorted { $0.position < $1.position }
            if sorted != local {
                bookmarks[key] = sorted.isEmpty ? nil : sorted
            }
        }
        scheduleSave()
    }

    private func send(_ bookmark: Bookmark, itemID: String, key: String) {
        Task {
            guard await AudiobookshelfAPI.shared.addBookmark(itemID: itemID, time: bookmark.position, title: bookmark.title) else { return }
            guard var list = bookmarks[key], let index = list.firstIndex(where: { $0.id == bookmark.id }) else { return }
            list[index].onServer = true
            bookmarks[key] = list
            scheduleSave()
        }
    }

    private func sendRemoval(at time: TimeInterval, itemID: String, key: String) {
        Task {
            guard await AudiobookshelfAPI.shared.removeBookmark(itemID: itemID, time: time) else { return }
            pendingRemovals[key]?.removeAll { abs($0 - time) < Self.samePlace }
            if pendingRemovals[key]?.isEmpty == true {
                pendingRemovals[key] = nil
            }
            scheduleSave()
        }
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Writes now, for the app leaving the foreground.
    func save() {
        saveTask?.cancel()
        saveTask = nil
        guard let url = Self.fileURL,
              let data = try? JSONEncoder().encode(Stored(bookmarks: bookmarks, pendingRemovals: pendingRemovals)) else { return }
        Self.io.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static var fileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("AudiobookBookmarks.json")
    }
}
