import Defaults
import Foundation
import Nuke
import SonosKit
import UIKit

/// The covers a shelf widget draws, beside its state in its App Group folder,
/// for the book shelf and Albums alike (`WidgetCatalogThumbnails` is Edit
/// Widget's small ones): each written once at the size it's shown, through
/// the phone's own image cache; one that won't load tried again after
/// `retryInterval`, not at every write (a playing book writes the shelves
/// every few seconds, and an unreachable server shouldn't be asked each
/// time); and taken away once no shelf names it.
@MainActor
final class WidgetCovers {
    /// The sizes written, as `ContentArtworkView` asks for them (a third of
    /// the pixels): a shelf's first item, which the small widget, the large
    /// one's lead and One Book show bigger (up to ~260 pt on the page-tall
    /// iPhone widget), and the rest (up to 120 pt on an iPad's extra large).
    /// Kept to about 9 MB decoded for a full shelf, inside a widget
    /// extension's memory.
    static let leadPoints: Double = 260
    static let points: Double = 120
    private static let retryInterval: TimeInterval = 10 * 60

    /// A cover to write: its file in the folder, and the image for it.
    struct Source {
        let name: String
        let request: ImageRequest
    }

    private let folder: BookShelfWidgetState.Folder
    /// Told once a cover lands, to write the shelves again with it.
    private let onWritten: @MainActor () -> Void
    /// The covers in the folder, by file name.
    private lazy var written: Set<String> = {
        let files = BookShelfWidgetState.directory(folder).flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        return Set(files.filter { $0.hasSuffix(".jpg") })
    }()
    /// The covers being fetched and written.
    private var underWay: Set<String> = []
    /// When each cover that didn't load was last tried.
    private var failures: [String: Date] = [:]

    init(folder: BookShelfWidgetState.Folder, onWritten: @escaping @MainActor () -> Void) {
        self.folder = folder
        self.onWritten = onWritten
    }

    /// `content`'s cover at the widget's size, named for its key; nil for
    /// one with no cover.
    static func source(for content: PlayableContent, key: String, isLead: Bool) -> Source? {
        guard let url = content.artwork ?? content.thumbnail else { return nil }
        let points = isLead ? leadPoints : Self.points
        let request = ContentArtworkView.artworkRequest(for: content, url: url, preferredSize: points)
        let pixels = Int(ContentArtworkView.maxPixelSize(for: points))
        return Source(name: BookShelfWidgetState.coverName(for: key, source: url.absoluteString, pixels: pixels), request: request)
    }

    /// The file a shelf names for `source`: it, once written, else one
    /// written before for `key` (another size, a cover since replaced)
    /// until it is.
    func file(for source: Source?, key: String) -> String? {
        guard let source else { return nil }
        return written.contains(source.name) ? source.name : written.first { $0.hasPrefix(BookShelfWidgetState.coverPrefix(for: key)) }
    }

    /// Fetches and writes those of `sources` with no file yet, and tells
    /// `onWritten` as each lands.
    func writeMissing(_ sources: [Source]) {
        for source in sources {
            guard !written.contains(source.name), !underWay.contains(source.name),
                  Date.now.timeIntervalSince(failures[source.name] ?? .distantPast) > Self.retryInterval,
                  let url = BookShelfWidgetState.coverURL(named: source.name, in: folder) else { continue }
            underWay.insert(source.name)
            Task {
                let isWritten = await Self.writeImage(source.request, to: url, quality: 0.85)
                underWay.remove(source.name)
                guard isWritten else {
                    failures[source.name] = .now
                    return
                }
                failures[source.name] = nil
                written.insert(source.name)
                onWritten()
            }
        }
    }

    /// Takes away the covers `named` leaves out. One on its way isn't named
    /// yet, and isn't among those written until it is.
    func removeAll(except named: Set<String>) {
        guard let directory = BookShelfWidgetState.directory(folder) else { return }
        for name in written where !named.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            written.remove(name)
        }
    }

    /// Fetches `request` (the phone's own cache first) and writes it to
    /// `url` as a JPEG. False when it didn't load or wasn't written.
    static func writeImage(_ request: ImageRequest, to url: URL, quality: CGFloat) async -> Bool {
        guard let image = try? await ImagePipeline.shared.image(for: request) else { return false }
        return await Task.detached(priority: .utility) {
            guard let data = image.jpegData(compressionQuality: quality) else { return false }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return (try? data.write(to: url, options: .atomic)) != nil
        }.value
    }
}
