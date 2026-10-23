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
    /// looked for, found or not: a book's page asks each time it draws.
    static func read(of book: PlayableContent) -> Audiobook? {
        let key = AudiobookProgressStore.key(for: book)
        if let kept = memory[key] { return kept }
        guard !missing.contains(key) else { return nil }
        guard var audiobook = CachesWriter.read(Audiobook.self, from: fileName(for: key)) else {
            missing.insert(key)
            return nil
        }
        audiobook.serverProgress = nil
        memory[key] = audiobook
        return audiobook
    }

    private static var memory: [String: Audiobook] = [:]
    /// Books looked for on disk and not there.
    private static var missing: Set<String> = []

    /// Holds `audiobook` as its book's last read for this launch, without
    /// writing it: a copy from elsewhere (a download's) to hand back fast.
    static func remember(_ audiobook: Audiobook) {
        memory[AudiobookProgressStore.key(for: audiobook.book)] = audiobook
    }

    /// Keeps `audiobook` as its book's last read.
    static func keep(_ audiobook: Audiobook) {
        var kept = audiobook
        kept.serverProgress = nil
        let key = AudiobookProgressStore.key(for: audiobook.book)
        memory[key] = kept
        let name = fileName(for: key)
        Task { await CachesWriter.shared.write(kept, to: name) }
    }

    /// AudiobookReads/<the book's progress key>.json.
    private static func fileName(for key: String) -> String {
        "AudiobookReads/\(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key).json"
    }
}
