import Foundation
import SonosKit

/// Each book as last read from its server, in Caches, so its page shows its
/// chapters, summary and length at once and reads it again behind them:
/// reading a book asks its server several times (its details, its files,
/// each file's chapter marks), seconds on a slow connection. A read whose
/// chapter marks didn't come keeps the last read's (`AudiobookLibrary.load`).
///
/// Only for showing: a play reads the server again, for its files and
/// where its other players left it. A book downloaded whole also has a copy
/// of its own (`AudiobookDownloads`), which plays with no server.
@MainActor
enum AudiobookReadCache {
    /// The book's last read, with no reading of where the server had the
    /// listener (that's stale; this device's own stands).
    static func read(of book: PlayableContent) -> Audiobook? {
        guard let url = url(for: book), let data = try? Data(contentsOf: url),
              var audiobook = try? JSONDecoder().decode(Audiobook.self, from: data) else { return nil }
        audiobook.serverProgress = nil
        return audiobook
    }

    /// Keeps `audiobook` as its book's last read.
    static func keep(_ audiobook: Audiobook) {
        guard let url = url(for: audiobook.book), let data = try? JSONEncoder().encode(audiobook) else { return }
        io.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private static let io = DispatchQueue(label: "dance.cue.audiobookReads", qos: .utility)

    /// Caches/AudiobookReads/<the book's progress key>.json.
    private static func url(for book: PlayableContent) -> URL? {
        guard let name = AudiobookProgressStore.key(for: book).addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return caches.appending(path: "AudiobookReads/\(name).json")
    }
}
