import Defaults
import Foundation
import MusicSearchKit
import OSLog
import SonosKit

/// A scan of the Plex libraries kept for books, under way: started from a
/// pull to refresh on a list of Plex books, which says "Scanning…" in its
/// title bar meanwhile. Plex scans on its own time, so this asks every
/// couple of seconds whether it's done, and stops waiting after
/// `longestWait`: the list then shows what's there, and the rest comes in
/// on the next refresh. Only the libraries chosen as books are scanned, not
/// the music library a genre-tagged book sits in, which can be large.
@MainActor
@Observable
final class PlexBookScan {
    static let shared = PlexBookScan()

    private(set) var isScanning = false

    private static let longestWait: Duration = .seconds(30)
    private static let pollInterval: Duration = .seconds(2)

    private init() {}

    /// The list's status while a scan runs.
    var status: String? {
        isScanning ? "Scanning…" : nil
    }

    func run() async {
        guard !isScanning else { return }
        let plex = PlexAPI.shared
        let keys = await plex.audiobookLibraries().map(\.key)
        guard !keys.isEmpty else {
            AudiobookLibrary.log.notice("plex scan: no library kept for books to scan")
            return
        }
        isScanning = true
        defer { isScanning = false }
        guard await plex.scan(sectionKeys: keys) else {
            AudiobookLibrary.log.error("plex scan of \(keys, privacy: .public): not started")
            return
        }
        AudiobookLibrary.log.info("plex scan of \(keys, privacy: .public) started")
        let clock = ContinuousClock()
        let start = clock.now
        // Plex takes a moment to begin, so the first answer of "not
        // scanning" comes after a wait.
        while clock.now - start < Self.longestWait {
            try? await Task.sleep(for: Self.pollInterval)
            guard await plex.isScanning(sectionKeys: keys) == true else { break }
        }
        AudiobookLibrary.log.info("plex scan of \(keys, privacy: .public) done or left after \((clock.now - start).formatted(.units(allowed: [.seconds])), privacy: .public)")
        // A library that came to have books shows the tab. Not one that
        // seems to have none: that's also what a server out of reach reads
        // as, and a blip shouldn't take the tab away.
        await AudiobookLibrary.checkPlexBooks()
    }
}
