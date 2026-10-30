import Defaults
import Foundation
import Nuke
import OSLog
import SonosKit

/// Writes the small covers Edit Widget lists a shelf widget's catalog with
/// (`BookShelfWidgetState.Catalog.thumbnailURL`), for the book shelf and
/// Albums alike: one an item, kept once written, a few hundred a
/// pass and one at a time, so a library of thousands doesn't flood its
/// server. An item whose cover didn't load is tried again next launch.
@MainActor
final class WidgetCatalogThumbnails {
    private static let log = Logger(subsystem: "dance.cue", category: "widgets")
    private static let points: Double = 44
    private static let perPass = 300

    private let folder: BookShelfWidgetState.Folder
    private var isWriting = false
    private var failures: Set<String> = []

    init(folder: BookShelfWidgetState.Folder) {
        self.folder = folder
    }

    /// Writes the covers `items` have none for yet, in their order.
    func writeMissing(for items: [(key: String, content: PlayableContent)]) {
        guard !isWriting, let directory = BookShelfWidgetState.Catalog.thumbnailDirectory(folder) else { return }
        let folder = folder
        // One listing of the folder, not a file check an item.
        let written = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        let missing = items.filter { key, _ in
            !failures.contains(key)
                && BookShelfWidgetState.Catalog.thumbnailURL(for: key, in: folder).map { !written.contains($0.lastPathComponent) } == true
        }
        .prefix(Self.perPass)
        guard !missing.isEmpty else { return }
        isWriting = true
        Task {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var writtenNow = 0
            for (key, content) in missing {
                // A book shows its Audible edition's cover, as on the phone.
                let drawn = ContentArtworkView.drawnContent(for: content)
                guard let source = drawn.artwork ?? drawn.thumbnail,
                      let url = BookShelfWidgetState.Catalog.thumbnailURL(for: key, in: folder) else {
                    // Nothing to fetch: not one of the next pass's either.
                    failures.insert(key)
                    continue
                }
                let request = ContentArtworkView.artworkRequest(for: drawn, url: source, preferredSize: Self.points)
                if await BookShelfWidgetPublisher.writeImage(request, to: url, quality: 0.7) {
                    writtenNow += 1
                } else {
                    failures.insert(key)
                }
            }
            isWriting = false
            Self.log.info("\(folder.rawValue, privacy: .public): \(writtenNow) of \(missing.count) catalog covers written")
        }
    }
}
