import Foundation
import Observation
import os
import SonosKit

/// The songs Shazam has named in Cue, newest first — what the Shazam
/// button found on every station, on this device or on a speaker.
///
/// Kept on this device in Application Support rather than read back from
/// `SHLibrary`: that library isn't there on visionOS, and it doesn't know
/// which station a song was heard on.
@MainActor
@Observable
final class RecognitionHistory {
    static let shared = RecognitionHistory()

    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        let title: String
        let artist: String?
        let artworkURL: URL?
        let appleMusicURL: URL?
        let shazamURL: URL?
        /// The Apple Music song, when the catalog has it — the row then
        /// plays, queues and adds to a playlist like any search result.
        let playable: PlayableContent?
        /// The station it was heard on, when known.
        let station: String?
        let date: Date

        /// Where a tap on a song without a catalog match goes.
        var link: URL? { appleMusicURL ?? shazamURL }
    }

    private(set) var entries: [Entry] = []

    /// Enough to scroll back through months of radio, small enough that
    /// the file stays a few hundred kilobytes.
    private static let limit = 500

    private init() {
        entries = Self.load()
    }

    func record(_ song: RecognizedSong, station: String?) {
        let entry = Entry(
            title: song.title,
            artist: song.artist,
            artworkURL: song.artworkURL ?? song.playable?.artwork,
            appleMusicURL: song.appleMusicURL,
            shazamURL: song.shazamURL,
            playable: song.playable,
            station: station,
            date: .now
        )
        // Tapping twice through the same song names it twice; keep the
        // latest only.
        if let first = entries.first, first.title == entry.title, first.artist == entry.artist {
            entries.removeFirst()
        }
        entries.insert(entry, at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
        save()
    }

    func remove(_ ids: Set<Entry.ID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    func removeAll() {
        entries.removeAll()
        save()
    }

    // MARK: - Storage

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Cue", category: "RecognitionHistory")

    private static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "RecognizedSongs.json")
    }

    private static func load() -> [Entry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([Entry].self, from: data)
        } catch {
            logger.error("Couldn't read recognized songs: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    private func save() {
        let url = Self.fileURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: url, options: .atomic)
        } catch {
            Self.logger.error("Couldn't save recognized songs: \(String(describing: error), privacy: .public)")
        }
    }
}
