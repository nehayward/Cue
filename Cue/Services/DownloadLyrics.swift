import Foundation
import MusicSearchKit
import OSLog
import SonosKit

/// Lyrics for downloaded Plex and Subsonic songs, looked up in the
/// background and kept with the download (`LyricsService`'s downloads
/// store, in Application Support) so a song taken offline has its words.
///
/// Slow on purpose. A downloaded album is a dozen lookups, and Plex fetches
/// LyricFind's lyrics for each, which it limits — a check of 150 songs at
/// a song a second shut LyricFind off for the server. So one song every
/// 30 seconds, while Cue is open, and when a song's server can't be asked
/// (LyricFind refusing, the server away, offline) that song waits an hour
/// at the back of the queue while the others go on; after three tries it
/// keeps what LRCLIB has, since some lyrics Plex lists LyricFind never
/// serves. Downloads
/// finished while Cue was closed, or before this existed, are picked up
/// at launch.
@MainActor
@Observable
final class DownloadLyrics {
    static let shared = DownloadLyrics()

    private init() {}

    /// Between one song's lookup and the next.
    static let spacing: Duration = .seconds(30)
    /// How long a song waits when its server couldn't be asked.
    static let backoff: TimeInterval = 60 * 60

    private static let log = Logger(subsystem: "dance.cue", category: "lyrics")

    /// Tries before a song settles for what LRCLIB has.
    static let triesBeforeSettling = 3

    /// Downloads whose lyrics are kept, by download key — for Downloads to
    /// mark them.
    private(set) var withLyrics: Set<String> = []

    @ObservationIgnored private var pending: [DownloadManager.Item] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    /// Songs whose server couldn't be asked, by download key.
    @ObservationIgnored private var tries: [String: Int] = [:]
    /// When each of those may be tried again.
    @ObservationIgnored private var retryAfter: [String: Date] = [:]

    /// What `LyricsService` keeps a song's lyrics under: the same as for
    /// the song playing, so playback finds them.
    static func key(for item: DownloadManager.Item) -> String {
        "\(item.service)|\(item.contentID)"
    }

    /// Notes which finished downloads have lyrics kept, at once, and queues
    /// the rest a little after launch so the lookups don't compete with it.
    func start() {
        Task {
            var missing: [DownloadManager.Item] = []
            for item in DownloadManager.shared.completed where [.plex, .subsonic].contains(item.service) {
                switch await LyricsService.shared.downloadLyrics(for: Self.key(for: item)) {
                case true?: withLyrics.insert(item.key)
                case false?: break
                case nil: missing.append(item)
                }
            }
            Self.log.info("\(self.withLyrics.count, privacy: .public) downloads have lyrics kept; \(missing.count, privacy: .public) to look up")
            try? await Task.sleep(for: .seconds(20))
            for item in missing {
                enqueue(item)
            }
        }
    }

    func enqueue(_ item: DownloadManager.Item) {
        guard [.plex, .subsonic].contains(item.service),
              !pending.contains(where: { $0.key == item.key }) else { return }
        pending.append(item)
        if worker == nil {
            worker = Task { await run() }
        }
    }

    /// A download removed: its lyrics go with it.
    func forget(_ item: DownloadManager.Item) {
        pending.removeAll { $0.key == item.key }
        withLyrics.remove(item.key)
        LyricsService.shared.forgetDownloadLyrics(for: Self.key(for: item))
    }

    private func run() async {
        defer { worker = nil }
        while !pending.isEmpty {
            // The first song not waiting out an hour since its last try; if
            // every one is, sleep until the soonest is due.
            let now = Date.now
            guard let index = pending.firstIndex(where: { (retryAfter[$0.key] ?? .distantPast) <= now }) else {
                let soonest = pending.compactMap { retryAfter[$0.key] }.min() ?? now
                try? await Task.sleep(for: .seconds(max(1, soonest.timeIntervalSince(now))))
                continue
            }
            let item = pending.remove(at: index)
            guard DownloadManager.shared.completed.contains(where: { $0.key == item.key }) else { continue }
            if let hasLyrics = await LyricsService.shared.downloadLyrics(for: Self.key(for: item)) {
                if hasLyrics { withLyrics.insert(item.key) }
                continue
            }
            let tried = tries[item.key, default: 0] + 1
            guard let found = await Self.song(for: item) else {
                // Its server couldn't be asked about it at all.
                waitAnHour(item, tried: tried)
                Self.log.info("\(item.title, privacy: .public): server away; its lyrics wait an hour")
                continue
            }
            let settling = tried >= Self.triesBeforeSettling
            switch await LyricsService.shared.keepDownloadLyrics(for: found.song, duration: found.duration, settling: settling) {
            case .kept(let hasLyrics):
                tries[item.key] = nil
                retryAfter[item.key] = nil
                if hasLyrics { withLyrics.insert(item.key) }
            case .later:
                waitAnHour(item, tried: tried)
                Self.log.info("\(item.title, privacy: .public): lyrics couldn't be looked up; they wait an hour")
            }
            if !pending.isEmpty {
                try? await Task.sleep(for: Self.spacing)
            }
        }
    }

    /// Back of the queue, not to be tried again for an hour — that song
    /// only, so one LyricFind refusal doesn't hold up the rest.
    private func waitAnHour(_ item: DownloadManager.Item, tried: Int) {
        tries[item.key] = tried
        retryAfter[item.key] = .now.addingTimeInterval(Self.backoff)
        pending.append(item)
    }

    /// The song as playback looks lyrics up for it — title, artist, album
    /// and length, which a download doesn't keep — read from its server.
    /// Its id is the download's, so the lyrics land under the playing
    /// song's key.
    private static func song(for item: DownloadManager.Item) async -> (song: PlayableContent, duration: TimeInterval)? {
        let content = MediaContent(service: item.service, id: item.contentID, type: .track, location: nil)
        switch item.service {
        case .plex:
            guard let ratingKey = DeviceStream.plexRatingKey(contentID: item.contentID),
                  let song = await PlexAPI.shared.lookupPlexSong(key: ratingKey)?.metadata?.first else { return nil }
            let duration = Double(song.duration ?? 0) / 1000
            let playable = PlayableContent(
                title: song.title,
                subtitle: song.grandparentTitle ?? "",
                thumbnail: nil,
                artwork: nil,
                content: content,
                metadata: .init(duration: .milliseconds(song.duration ?? 0), artist: song.grandparentTitle, album: song.parentTitle)
            )
            return (playable, duration)
        case .subsonic:
            guard let song = await SubsonicAPI.shared.song(for: item.contentID), let title = song.title else { return nil }
            let duration = Double(song.duration ?? 0)
            let playable = PlayableContent(
                title: title,
                subtitle: song.artist ?? "",
                thumbnail: nil,
                artwork: nil,
                content: content,
                metadata: .init(duration: .seconds(duration), artist: song.artist, album: song.album)
            )
            return (playable, duration)
        default:
            return nil
        }
    }
}
