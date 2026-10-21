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
    /// listener (that's stale; this device's own stands). From memory once
    /// read: a book's page asks as it's made, which can be often.
    static func read(of book: PlayableContent) -> Audiobook? {
        let key = AudiobookProgressStore.key(for: book)
        if let kept = memory[key] { return kept }
        guard let url = url(for: book), let data = try? Data(contentsOf: url),
              var audiobook = try? JSONDecoder().decode(Audiobook.self, from: data) else { return nil }
        audiobook.serverProgress = nil
        memory[key] = audiobook
        return audiobook
    }

    private static var memory: [String: Audiobook] = [:]

    /// Holds `audiobook` as its book's last read for this launch, without
    /// writing it: a copy from elsewhere (a download's) to hand back fast.
    static func remember(_ audiobook: Audiobook) {
        memory[AudiobookProgressStore.key(for: audiobook.book)] = audiobook
    }

    /// Keeps `audiobook` as its book's last read.
    static func keep(_ audiobook: Audiobook) {
        var kept = audiobook
        kept.serverProgress = nil
        memory[AudiobookProgressStore.key(for: audiobook.book)] = kept
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
