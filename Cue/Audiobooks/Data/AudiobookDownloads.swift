import Foundation
import OSLog
import SonosKit

/// What a book downloaded whole needs with no network: the book read whole
/// — its files, how they lie end to end, its chapters — kept beside the
/// downloads when the download starts, and refreshed whenever the server
/// is read again. `AudiobookLibrary.load` falls back on it when the server
/// can't be read, or straight away offline, so the book opens, resumes and
/// moves by chapter from its files on this device. Its files themselves
/// are the download manager's (`DownloadManager.Item.isBookFile`).
@MainActor
enum AudiobookDownloads {
    private static let log = Logger(subsystem: "dance.cue", category: "audiobooks")

    /// Reads the book from its server for a download, keeps the copy, and
    /// hands back its files. Nil when the server couldn't be read.
    static func prepare(_ book: PlayableContent) async -> [PlayableContent]? {
        guard let audiobook = await AudiobookLibrary.loadFromServer(book) else { return nil }
        save(audiobook)
        return audiobook.parts
    }

    /// The copy kept for a downloaded book, with no reading of where the
    /// server had the listener (that's stale; this device's own stands).
    static func copy(of book: PlayableContent) -> Audiobook? {
        guard let data = try? Data(contentsOf: url(forContainerKey: DownloadManager.containerKey(for: book))),
              var audiobook = try? JSONDecoder().decode(Audiobook.self, from: data) else { return nil }
        audiobook.serverProgress = nil
        audiobook.filesMissing = nil
        return audiobook
    }

    /// Whether the book is downloaded whole, every file on this device.
    static func isDownloaded(_ book: PlayableContent) -> Bool {
        DownloadManager.shared.isDownloaded(contentsOf: book)
    }

    /// Whether every one of `audiobook`'s files is on this device, so it
    /// plays with no server.
    static func hasAllFiles(_ audiobook: Audiobook) -> Bool {
        let manager = DownloadManager.shared
        return !audiobook.parts.isEmpty && audiobook.parts.allSatisfy { manager.localURL(for: $0) != nil }
    }

    /// Keeps `audiobook` as its download's copy: when it's downloaded, or
    /// on its way, read again from the server.
    static func refresh(_ audiobook: Audiobook) {
        guard DownloadManager.shared.containerState(for: audiobook.book) != nil else { return }
        save(audiobook)
    }

    /// Whether any book is on this device whole: offline, the Audiobooks
    /// tab stays for them.
    static var hasDownloadedBooks: Bool {
        let manager = DownloadManager.shared
        return manager.containers.values.contains { $0.type == .audiobook && manager.containerState(key: $0.key) == .downloaded }
    }

    /// The books downloaded or on their way (`completeOnly`: only those
    /// whole on this device), newest first, as the shelf lists them: from
    /// what the download keeps of each (its title, author and cover), so a
    /// shelf drawn often reads nothing from disk.
    static func downloadedBooks(completeOnly: Bool = false) -> [PlayableContent] {
        let manager = DownloadManager.shared
        return manager.containers.values
            .filter { $0.type == .audiobook && (!completeOnly || manager.containerState(key: $0.key) == .downloaded) }
            .sorted { $0.createdAt > $1.createdAt }
            .map(book(for:))
    }

    /// The book a download is of, from what the download keeps of it.
    static func book(for container: DownloadManager.Container) -> PlayableContent {
        PlayableContent(
            title: container.title,
            subtitle: container.subtitle,
            thumbnail: container.artwork,
            artwork: container.artwork,
            content: .init(service: container.service, id: container.contentID, type: .audiobook, location: nil)
        )
    }

    static func removeCopy(containerKey: String) {
        try? FileManager.default.removeItem(at: url(forContainerKey: containerKey))
    }

    // MARK: - Storage

    private static func save(_ audiobook: Audiobook) {
        var kept = audiobook
        kept.serverProgress = nil
        kept.filesMissing = nil
        let url = url(forContainerKey: DownloadManager.containerKey(for: audiobook.book))
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(kept).write(to: url, options: .atomic)
        } catch {
            log.error("couldn't keep \(audiobook.book.title, privacy: .public) for offline: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Beside the downloads, so it's kept and removed with them.
    private static func url(forContainerKey key: String) -> URL {
        DownloadManager.directory
            .appendingPathComponent("Books", isDirectory: true)
            .appendingPathComponent(key)
            .appendingPathExtension("json")
    }
}
