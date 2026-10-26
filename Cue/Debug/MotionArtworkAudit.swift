#if DEBUG
import Foundation
import MusicKit
import MusicSearchKit
import OSLog

/// Whether Cue finds the albums' moving covers: through the API, which
/// Apple has said keeps them from third-party apps, and on the albums'
/// pages on music.apple.com, which `MotionArtworkService` reads when the API
/// has none. Debug builds only.
///
/// Launched with `-MotionArtworkAudit YES`, it finds a few albums that have
/// a moving cover in Apple Music, by search so no catalog id goes stale, and
/// asks for each one's `editorialVideo` and reads its page, logging under
/// `motionartwork` the shapes and videos each gave, or that it gave none,
/// then a count. `-MotionArtworkAuditAlbums 1649434004,1440857781` asks about those
/// catalog albums instead. Run it with `Scripts/deploy-to-iphone.sh --logs`
/// and `CUE_LOG_FILTER=motionartwork`.
@MainActor
enum MotionArtworkAudit {
    private static let log = Logger(subsystem: "dance.cue", category: "motionartwork")

    /// Albums Apple Music shows with a moving cover.
    private static let searches = [
        "Midnights Taylor Swift",
        "GUTS Olivia Rodrigo",
        "HIT ME HARD AND SOFT Billie Eilish",
        "After Hours The Weeknd",
        "SOS SZA",
    ]

    static func startIfRequested() {
        let defaults = UserDefaults.standard
        if let ids = defaults.string(forKey: "MotionArtworkAuditAlbums") {
            let albumIDs = ids.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            Task { await run(albumIDs: albumIDs) }
        } else if defaults.bool(forKey: "MotionArtworkAudit") {
            Task { await run(albumIDs: nil) }
        }
    }

    /// Asks about `albumIDs`, or the albums `searches` finds.
    private static func run(albumIDs: [String]?) async {
        try? await Task.sleep(for: .seconds(3))
        guard MusicAuthorization.currentStatus == .authorized else {
            log.error("audit: Apple Music isn't allowed on this device, so Apple can't be asked")
            return
        }
        var ids = albumIDs ?? []
        if albumIDs == nil {
            for term in searches {
                var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Album.self])
                request.limit = 1
                guard let album = try? await request.response().albums.first else {
                    log.error("audit: no album for \(term, privacy: .public)")
                    continue
                }
                log.info("audit: \(term, privacy: .public) is \(album.title, privacy: .public) (\(album.id.rawValue, privacy: .public))")
                ids.append(album.id.rawValue)
            }
        }
        var fromAPI = 0
        var withoutField = 0
        var fromPage = 0
        for id in ids {
            do {
                if let videos = try await AppleMusicAPI.shared.editorialVideos(albumID: id) {
                    if AppleMotionArtwork(videos: videos) != nil { fromAPI += 1 }
                    logVideos(videos, album: id, from: "editorialVideo")
                } else {
                    withoutField += 1
                    log.notice("audit: album \(id, privacy: .public) came back with no editorialVideo")
                }
            } catch {
                log.error("audit: album \(id, privacy: .public) failed in the API: \(error.localizedDescription, privacy: .public)")
            }
            do {
                if let videos = try await AppleMusicAPI.shared.albumPageVideos(albumID: id) {
                    if AppleMotionArtwork(videos: videos) != nil { fromPage += 1 }
                    logVideos(videos, album: id, from: "page")
                } else {
                    log.error("audit: album \(id, privacy: .public)'s page isn't laid out as expected")
                }
            } catch {
                log.error("audit: album \(id, privacy: .public)'s page failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        log.notice("audit: of \(ids.count) albums, \(fromAPI) came with a video from the API (\(withoutField) had no editorialVideo in the response) and \(fromPage) from their pages")
    }

    private static func logVideos(_ videos: [String: URL], album id: String, from source: String) {
        for (shape, url) in videos.sorted(by: { $0.key < $1.key }) {
            log.notice("audit: album \(id, privacy: .public) \(source, privacy: .public) \(shape, privacy: .public): \(url.absoluteString, privacy: .public)")
        }
        if videos.isEmpty {
            log.notice("audit: album \(id, privacy: .public) \(source, privacy: .public) has no video")
        }
    }
}
#endif
