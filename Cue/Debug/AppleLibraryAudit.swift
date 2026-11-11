#if DEBUG
import Foundation
import MusicKit
import MusicSearchKit
import OSLog
import SonosKit

/// Reads the Apple Music library the way its lists do, every Show pick,
/// order and direction, and logs what each gives back: how many, the first
/// few, which carry a favorite's star and how long it took. For checking
/// the lists against a real library without opening each one. Debug builds
/// only.
///
/// Launched with `-AppleLibraryAudit YES`, or on the Mac with
/// `AppleLibraryAudit=1` in the environment (`launch_mac_app
/// AppleLibraryAudit=1`, as the Mac scripts pass no arguments). Logged under
/// `dance.cue` `apple-library-audit`. Reads only: nothing is favorited.
@MainActor
enum AppleLibraryAudit {
    private static let log = Logger(subsystem: "dance.cue", category: "apple-library-audit")

    static func startIfRequested() {
        guard UserDefaults.standard.bool(forKey: "AppleLibraryAudit")
                || ProcessInfo.processInfo.environment["AppleLibraryAudit"] == "1" else { return }
        Task {
            // After the launch's own reads, and Apple Music's authorization.
            try? await Task.sleep(for: .seconds(3))
            await run()
        }
    }

    private static func run() async {
        let browse = AppleMusicBrowseService.shared
        log.info("start: Apple Music \(String(describing: MusicAuthorization.currentStatus), privacy: .public), held \(AppleMusicPermission.isHeld)")
        for resource in [AppleLibraryResource.albums, .artists, .songs] {
            for filter in AppleLibraryLists.filters(for: resource, browseService: browse) {
                for sort in filter.sortOptions {
                    for descending in sort.isReversible ? [false, true] : [false] {
                        await report("\(filter.title) by \(sort.name)\(descending ? " (descending)" : "")", sort: sort, descending: descending)
                    }
                }
            }
        }
        for sort in AppleLibraryLists.favoritesShelfSortOptions(browseService: browse) {
            await report("Favorites by \(sort.name)", sort: sort, descending: sort.defaultsToDescending, showsDates: true)
        }

        // A MusicKit album row marked a favorite finds its web id, which
        // its favorite button sends.
        let albums = await browse.libraryAlbums(marksFavorites: true)
        if let favorite = albums.first(where: { ($0.metadata?.userRating ?? 0) > 0 }) {
            let id = await browse.webLibraryID(for: favorite)
            log.info("web id of \(favorite.title, privacy: .public) (\(favorite.id, privacy: .public)): \(id ?? "none", privacy: .public)")
        } else {
            log.info("no favorite among the first page of albums")
        }
        log.info("done")
    }

    private static func report(_ name: String, sort: PlayableListSort, descending: Bool, showsDates: Bool = false) async {
        log.info("→ \(name, privacy: .public)")
        let clock = ContinuousClock()
        let started = clock.now
        let first = await sort.action(0, descending)
        let second = first.count >= 100 ? await sort.action(first.count, descending) : []
        let elapsed = started.duration(to: clock.now)
        let starred = (first + second).filter { ($0.metadata?.userRating ?? 0) > 0 }.count
        let musicKit = first.filter { $0.content.id.allSatisfy(\.isNumber) }.count
        let browse = AppleMusicBrowseService.shared
        let sample = first.prefix(6).map { item in
            var line = item.title
            if let artist = item.metadata?.artist, item.content.type.isArtist == false { line += " – \(artist)" }
            if showsDates { line += " [\(item.content.type) added \(browse.dates(of: item.id)?.added ?? "-") released \(browse.dates(of: item.id)?.released ?? "-")]" }
            if (item.metadata?.userRating ?? 0) > 0 { line += " ★" }
            return line
        }
        log.info("""
        \(name, privacy: .public): \(first.count) + \(second.count) in \(elapsed.formatted(.units(allowed: [.milliseconds])), privacy: .public), \
        \(starred) starred, \(musicKit) MusicKit rows | \(sample.joined(separator: " | "), privacy: .public)
        """)
    }
}
#endif
