import CryptoKit
import Defaults
import Foundation
import MusicSearchKit
import Observation
import OSLog
import SonosKit

/// The lyrics of the song the player shows, for the lyrics view and its
/// button.
///
/// Where they come from, in order:
/// 1. The song's own service: Plex's lyric streams, Subsonic's lyrics, a
///    Files song's sidecar `.lrc` or tags.
/// 2. LRCLIB, while Look Up Lyrics Online is on and the service had none
///    timed — taken over the service's plain lyrics only when LRCLIB's are
///    timed. Apple Music, whose lyrics MusicKit doesn't give out, always
///    comes here.
///
/// One song at a time, asked for by the player while it's open, so the
/// button knows before it's tapped. Answers are kept in memory and on disk
/// (Caches), so a song seen before has its lyrics at once and offline; a
/// song with none is asked again after a few days, since LRCLIB grows. A
/// lookup that got no answer at all — offline, a server down — isn't
/// kept, and is tried again the next time the player asks. Nor is LRCLIB's
/// answer for a song whose own server couldn't be asked: it's shown, kept
/// in memory for a few minutes, and the server is asked again after that,
/// so a Plex server that was slow to answer once doesn't lose its
/// LyricFind lyrics to LRCLIB for good.
///
/// Stations have no lyrics here: their clock is the station's, not the
/// song's, so nothing could follow it.
@MainActor
@Observable
final class LyricsService {
    static let shared = LyricsService()

    enum State: Equatable {
        /// Nothing to look for: no song, or a station.
        case unavailable
        case loading
        case loaded(Lyrics)
        /// Looked everywhere; there are none.
        case none
        /// Couldn't look — offline, or a server didn't answer.
        case failed
    }

    /// Where an answer came from, for the debug badge on the lyrics.
    enum Origin: String {
        case memory
        case disk
        case lookup
    }

    /// What the song on screen has, once `request` has been told about it.
    private(set) var state: State = .unavailable
    /// Where `state`'s answer came from; `nil` until there is one.
    private(set) var origin: Origin?

    /// The song `state` is for.
    @ObservationIgnored private(set) var key: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The running lookup is waiting for the song's length (see `request`).
    @ObservationIgnored private var isWaitingForDuration = false
    @ObservationIgnored private var failedAt: Date?
    @ObservationIgnored private var memory: [String: LyricsStore.Entry] = [:]
    @ObservationIgnored private let store = LyricsStore()

    private static let log = Logger(subsystem: "dance.cue", category: "lyrics")

    /// How long a lookup that found nothing is believed.
    static let noneLifetime: TimeInterval = 3 * 24 * 60 * 60
    /// How long an answer found while the song's own server couldn't be
    /// asked stands before the server is asked again.
    static let provisionalLifetime: TimeInterval = 5 * 60
    /// How soon a lookup that failed may be tried again.
    static let retryInterval: TimeInterval = 20
    /// How long a song with no length yet is given to report one before
    /// LRCLIB is asked without it. A speaker sends the length a moment
    /// after the song changes, and without it LRCLIB can't tell a radio
    /// edit from the album cut.
    static let durationWait: Duration = .seconds(2)

    private init() {}

    var isOnlineLookupEnabled: Bool {
        UserDefaults.standard.object(forKey: AppStorageKeys.lyricsOnlineLookup) as? Bool ?? true
    }

    /// The song a controller is playing, when it's one that can have lyrics.
    static func song(of controller: any PlaybackController) -> PlayableContent? {
        guard let item = controller.nowPlayingDisplay,
              !item.content.type.isRadio,
              item.metadata?.radioStation != true,
              !item.title.isEmpty else { return nil }
        if let room = controller.group?.coordinatorRoom,
           room.radioStation != nil || room.track.metadata?.contentType == .radio {
            return nil
        }
        return item
    }

    static func key(for item: PlayableContent) -> String {
        "\(item.content.service)|\(item.content.id)"
    }

    /// Looks up `item`'s lyrics, unless that's already done or under way.
    /// `duration` is the song's length in seconds, 0 while unknown; asked
    /// again once it's known, a lookup still waiting for it goes ahead
    /// with it.
    func request(for item: PlayableContent?, duration: TimeInterval) {
        guard let item else {
            task?.cancel()
            key = nil
            state = .unavailable
            origin = nil
            return
        }
        let key = Self.key(for: item)
        let lookUpOnline = isOnlineLookupEnabled
        if key == self.key {
            switch state {
            case .loading:
                // Under way, unless it's waiting for a length that's now here.
                guard isWaitingForDuration, duration > 0 else { return }
            case .failed:
                if let failedAt, Date.now.timeIntervalSince(failedAt) < Self.retryInterval { return }
            case .loaded, .none, .unavailable:
                // Still the answer, unless Look Up Lyrics Online changed
                // what it should cover.
                if memory[key]?.isUsable(lookUpOnline: lookUpOnline) ?? false { return }
            }
        }
        task?.cancel()
        self.key = key
        failedAt = nil

        if let entry = memory[key], entry.isUsable(lookUpOnline: lookUpOnline) {
            state = entry.lyrics.map(State.loaded) ?? .none
            origin = .memory
            return
        }
        state = .loading
        origin = nil
        isWaitingForDuration = duration <= 0
        Self.log.info("\(item.title, privacy: .public): looking up \(String(describing: item.content.service), privacy: .public) \(item.content.id, privacy: .public), \(Int(duration), privacy: .public) s")
        task = Task { [store] in
            if let entry = await store.entry(for: key), entry.isUsable(lookUpOnline: lookUpOnline) {
                guard !Task.isCancelled, self.key == key else { return }
                memory[key] = entry
                isWaitingForDuration = false
                state = entry.lyrics.map(State.loaded) ?? .none
                origin = .disk
                return
            }
            if duration <= 0 {
                try? await Task.sleep(for: Self.durationWait)
                guard !Task.isCancelled else { return }
            }
            isWaitingForDuration = false
            do {
                let (lyrics, serviceFailed) = try await Self.find(item, duration: duration, lookUpOnline: lookUpOnline)
                let entry = LyricsStore.Entry(lyrics: lyrics, lookedOnline: lookUpOnline, storedAt: .now, isProvisional: serviceFailed)
                memory[key] = entry
                if !serviceFailed {
                    await store.store(entry, for: key)
                }
                guard !Task.isCancelled, self.key == key else { return }
                state = lyrics.map(State.loaded) ?? .none
                origin = .lookup
                Self.log.info("\(item.title, privacy: .public): \(lyrics.map { "\($0.source.rawValue), \($0.isSynced ? "timed" : "plain"), \($0.lines.count) lines" } ?? "none", privacy: .public)")
            } catch {
                guard !Task.isCancelled, self.key == key else { return }
                failedAt = .now
                state = .failed
                Self.log.error("\(item.title, privacy: .public): lookup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Asks again for the song on screen after a failed lookup.
    func retry(for item: PlayableContent?, duration: TimeInterval) {
        failedAt = nil
        request(for: item, duration: duration)
    }

    // MARK: - Finding

    /// The service's own lyrics, then LRCLIB's, and whether the service
    /// couldn't be asked (so the answer is only provisional). Throws only
    /// when nothing could be asked at all.
    private static func find(_ item: PlayableContent, duration: TimeInterval, lookUpOnline: Bool) async throws -> (Lyrics?, serviceFailed: Bool) {
        var own: Lyrics?
        var serviceFailed = false
        do {
            own = try await serviceLyrics(for: item)
            log.info("\(item.title, privacy: .public): \(String(describing: item.content.service), privacy: .public) has \(own.map { $0.isSynced ? "timed" : "plain" } ?? "none", privacy: .public)")
        } catch {
            serviceFailed = true
            log.info("\(item.title, privacy: .public): \(String(describing: item.content.service), privacy: .public) couldn't be asked: \(String(describing: error), privacy: .public)")
        }
        if let own, own.isSynced || own.isInstrumental {
            return (own, false)
        }
        guard lookUpOnline else { return (own, serviceFailed) }
        do {
            let online = try await LRCLibAPI.lyrics(
                title: item.title,
                artist: item.metadata?.artist ?? item.subtitle,
                album: item.metadata?.album,
                duration: duration > 0 ? duration : nil
            )
            if let online, online.isSynced || own == nil {
                return (online, serviceFailed)
            }
        } catch {
            if own == nil { throw error }
        }
        return (own, serviceFailed)
    }

    /// The song's own server's lyrics: `nil` when it answered with none,
    /// throwing when it couldn't be asked.
    private static func serviceLyrics(for item: PlayableContent) async throws -> Lyrics? {
        switch item.content.service {
        case .plex:
            guard let ratingKey = item.plexRatingKey else {
                log.info("\(item.title, privacy: .public): no Plex rating key in \(item.content.id, privacy: .public)")
                return nil
            }
            return try await PlexAPI.shared.lyrics(ratingKey: ratingKey)
        case .subsonic:
            guard SubsonicAPI.shared.isConfigured else { return nil }
            return await SubsonicAPI.shared.lyrics(
                songID: item.content.id,
                artist: item.metadata?.artist ?? item.subtitle,
                title: item.title
            )
        case .files:
            guard let text = await FilesLibraryService.shared.lyrics(trackID: item.content.id) else { return nil }
            return Lyrics.parse(text, source: .file)
        default:
            return nil
        }
    }
}

/// Lyrics already looked up, a file per song in Caches/Lyrics, found or
/// not. The system may clear it; nothing here is the only copy.
actor LyricsStore {
    struct Entry: Codable {
        /// `nil`: looked, found none.
        let lyrics: Lyrics?
        /// LRCLIB was asked, so a miss is a miss everywhere.
        let lookedOnline: Bool
        let storedAt: Date
        /// Found while the song's own server couldn't be asked: kept in
        /// memory only, and only for a few minutes.
        var isProvisional = false

        /// Still the answer: found lyrics last, unless LRCLIB's while
        /// looking online is now off; a miss lasts a few days, and only
        /// while it covers everywhere that's now looked; a provisional
        /// answer, a few minutes.
        func isUsable(lookUpOnline: Bool) -> Bool {
            if isProvisional, Date.now.timeIntervalSince(storedAt) > LyricsService.provisionalLifetime {
                return false
            }
            if let lyrics {
                return lookUpOnline || lyrics.source != .lrclib
            }
            if lookUpOnline, !lookedOnline { return false }
            return Date.now.timeIntervalSince(storedAt) < LyricsService.noneLifetime
        }
    }

    /// Past this many songs, the ones used longest ago go.
    private static let limit = 2000

    /// Bumped when what's kept changes meaning. 2: an answer found while
    /// the song's own server couldn't be asked is no longer kept, so the
    /// first version's may hide a server's lyrics behind LRCLIB's.
    private static let version = 2

    private let root: URL?
    private let directory: URL?
    private var isPrepared = false
    private var storedSinceTrim = 0

    init() {
        root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Lyrics", isDirectory: true)
        directory = root?.appendingPathComponent("\(Self.version)", isDirectory: true)
    }

    func entry(for key: String) -> Entry? {
        prepare()
        guard let url = fileURL(for: key),
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        // Used now, so the trim keeps it.
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: url.path)
        return entry
    }

    func store(_ entry: Entry, for key: String) {
        prepare()
        guard let url = fileURL(for: key), let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: url, options: .atomic)
        storedSinceTrim += 1
        if storedSinceTrim >= 100 {
            trim()
        }
    }

    private func prepare() {
        guard !isPrepared, let directory else { return }
        isPrepared = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Earlier versions' files, and their folders.
        if let root, let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for item in items where item.lastPathComponent != directory.lastPathComponent {
                try? FileManager.default.removeItem(at: item)
            }
        }
        trim()
    }

    private func trim() {
        storedSinceTrim = 0
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]),
              files.count > Self.limit else { return }
        let dated = files.map { file in
            (file, (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for (file, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(files.count - Self.limit) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Hashed: ids carry characters a file name can't, and some run long.
    private func fileURL(for key: String) -> URL? {
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent(digest).appendingPathExtension("json")
    }
}
