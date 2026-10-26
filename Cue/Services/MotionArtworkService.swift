import Defaults
import Foundation
import MusicKit
import MusicSearchKit
import Network
import Observation
import OSLog
import SonosKit

/// When Apple Music's moving covers play: Settings ▸ Appearance ▸ Video
/// Covers. Wi‑Fi Only by default, since each turn of a loop comes down again.
enum VideoCoverPreference: String, CaseIterable, Identifiable {
    case on
    case wifiOnly
    case off

    var id: String { rawValue }

    static let defaultValue: VideoCoverPreference = .wifiOnly

    var title: String {
        switch self {
        case .on: "On"
        case .wifiOnly: "Wi‑Fi Only"
        case .off: "Off"
        }
    }
}

/// Apple Music's moving covers (`AppleMotionArtwork`) for the player and an
/// album's page, drawn by `MotionArtworkOverlay`.
///
/// Apple lists them per album, so a song is looked up as its album: a
/// library song's catalog twin first, then the album it's on, then that
/// album's videos. Every answer is kept, a video for 30 days and none for 7,
/// in Caches/MotionArtwork.json, with the album a song was found on, by the
/// song and by its album's title and artist: the next song of an album
/// already looked up finds the video at once rather than after a request, so
/// the cover doesn't stop moving from one song to the next.
///
/// Nothing here asks for Apple Music: with no permission given there's no
/// lookup, and a speaker playing Apple Music from its own account shows its
/// still cover. Each album's answer is logged under `motionartwork`, saying
/// when the response had no `editorialVideo` at all, which is how Apple
/// keeping the videos from third-party apps would show.
@MainActor
@Observable
final class MotionArtworkService {
    static let shared = MotionArtworkService()

    /// What's known about an item's video without asking Apple.
    enum Answer: Equatable {
        case unknown
        case noVideo
        case video(AppleMotionArtwork)
    }

    /// On cellular or a personal hotspot. Taken as so until the first
    /// reading, a moment after launch, so Wi‑Fi Only never starts a video
    /// before it's known.
    private(set) var isOnExpensivePath = true
    /// Low Data Mode.
    private(set) var isOnConstrainedPath = false
    private(set) var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    @ObservationIgnored private var store: Store
    @ObservationIgnored private var lookups: [String: Task<AppleMotionArtwork?, Never>] = [:]
    /// When a request for a key failed, so it isn't asked again at once.
    @ObservationIgnored private var failures: [String: Date] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var powerObserver: NSObjectProtocol?

    private static let log = Logger(subsystem: "dance.cue", category: "motionartwork")
    private static let fileName = "MotionArtwork.json"
    /// How soon a request that failed may be made again.
    static let retryInterval: TimeInterval = 10 * 60
    /// Songs and album names kept, beyond which the oldest lookups go.
    private static let albumIDLimit = 4000

    private init() {
        store = CachesWriter.read(Store.self, from: Self.fileName) ?? Store()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            Task { @MainActor in
                self?.isOnExpensivePath = expensive
                self?.isOnConstrainedPath = constrained
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "dance.cue.motionartwork.path", qos: .utility))
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    // MARK: - When

    /// Whether a video may play now under `preference`. Never in Low Power
    /// Mode, Low Data Mode or Offline Mode, nor in a car: the phone's screen
    /// isn't what's watched there, and a player starting in Cue's process
    /// could take the car's Now Playing from MusicKit's (see CarPlay in
    /// CLAUDE.md). Wi‑Fi Only also waits out cellular and hotspots.
    func allowsVideo(_ preference: VideoCoverPreference) -> Bool {
        switch preference {
        case .off: return false
        case .wifiOnly where isOnExpensivePath: return false
        case .on, .wifiOnly: break
        }
        return !isLowPower && !isOnConstrainedPath && !OfflineMode.shared.isActive && !SonosService.shared.isInCar
    }

    // MARK: - Lookup

    /// What `content` is looked up by: a song's or an album's id. Nil for
    /// anything Apple has no moving cover for: another service, a station,
    /// a playlist.
    static func lookupKey(for content: PlayableContent) -> String? {
        guard content.content.service == .apple, !content.content.id.isEmpty else { return nil }
        switch content.content.type {
        case .track, .libraryTrack: return "song:\(content.content.id)"
        case .album: return "album:\(content.content.id)"
        case .libraryAlbum: return "library-album:\(content.content.id)"
        default: return nil
        }
    }

    /// A song's album by name, which the album's other songs share.
    private static func albumNameKey(for content: PlayableContent) -> String? {
        guard [.track, .libraryTrack].contains(content.content.type),
              let album = content.metadata?.album, !album.isEmpty else { return nil }
        return "name:\(album.lowercased())|\((content.metadata?.artist ?? "").lowercased())"
    }

    /// What's already known about `content`'s video, with no request.
    func known(for content: PlayableContent) -> Answer {
        guard let key = Self.lookupKey(for: content) else { return .noVideo }
        guard let known = knownAlbumID(key: key, content: content) else { return .unknown }
        guard let albumID = known else { return .noVideo }
        guard let entry = store.albums[albumID], !entry.isExpired else { return .unknown }
        guard let artwork = entry.artwork else { return .noVideo }
        return .video(artwork)
    }

    /// `content`'s video, asked of Apple when it isn't known yet. Nil when it
    /// has none, Apple Music isn't allowed, or Apple couldn't be asked.
    func artwork(for content: PlayableContent) async -> AppleMotionArtwork? {
        guard let key = Self.lookupKey(for: content),
              MusicAuthorization.currentStatus == .authorized else { return nil }
        if let lookup = lookups[key] { return await lookup.value }
        let lookup = Task { await self.resolve(key: key, content: content) }
        lookups[key] = lookup
        let artwork = await lookup.value
        lookups[key] = nil
        return artwork
    }

    /// The catalog album `key` is on as far as is known: `.some(nil)` for
    /// one known to have none, nil for not known yet.
    private func knownAlbumID(key: String, content: PlayableContent) -> String?? {
        if key.hasPrefix("album:") { return String(key.dropFirst("album:".count)) }
        if let id = store.albumIDs[key] {
            if id.isEmpty { return .some(nil) }
            return id
        }
        if let nameKey = Self.albumNameKey(for: content), let id = store.albumIDs[nameKey], !id.isEmpty { return id }
        return nil
    }

    private func resolve(key: String, content: PlayableContent) async -> AppleMotionArtwork? {
        let albumID: String?
        if let known = knownAlbumID(key: key, content: content) {
            albumID = known
        } else {
            albumID = await lookUpAlbumID(key: key, content: content)
        }
        guard let albumID else { return nil }
        return await artwork(albumID: albumID)
    }

    private func lookUpAlbumID(key: String, content: PlayableContent) async -> String? {
        guard !hasRecentlyFailed(key) else { return nil }
        let api = AppleMusicAPI.shared
        let id = content.content.id
        do {
            let albumID = key.hasPrefix("song:")
                ? try await api.catalogAlbumID(forSong: id)
                : try await api.catalogAlbumID(forLibraryAlbum: id)
            remember(albumID: albumID, for: key)
            if let albumID, let nameKey = Self.albumNameKey(for: content) {
                remember(albumID: albumID, for: nameKey)
            }
            if albumID == nil {
                Self.log.info("\(key, privacy: .public): no catalog album")
            }
            save()
            return albumID
        } catch {
            failures[key] = .now
            Self.log.error("\(key, privacy: .public): album lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func artwork(albumID: String) async -> AppleMotionArtwork? {
        if let entry = store.albums[albumID], !entry.isExpired { return entry.artwork }
        let failureKey = "album:\(albumID)"
        guard !hasRecentlyFailed(failureKey) else { return nil }
        do {
            let videos = try await AppleMusicAPI.shared.editorialVideos(albumID: albumID)
            let artwork = videos.flatMap { AppleMotionArtwork(videos: $0) }
            if let videos {
                let shapes = videos.keys.sorted().joined(separator: ", ")
                Self.log.info("album \(albumID, privacy: .public): editorialVideo [\(shapes, privacy: .public)], square \(artwork?.square != nil), tall \(artwork?.tall != nil)")
            } else {
                Self.log.info("album \(albumID, privacy: .public): no editorialVideo in the response")
            }
            store.albums[albumID] = Entry(artwork: artwork, checkedAt: .now)
            save()
            return artwork
        } catch {
            failures[failureKey] = .now
            Self.log.error("album \(albumID, privacy: .public): video lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func hasRecentlyFailed(_ key: String) -> Bool {
        guard let failedAt = failures[key] else { return false }
        return Date.now.timeIntervalSince(failedAt) < Self.retryInterval
    }

    // MARK: - Keeping

    private func remember(albumID: String?, for key: String) {
        if store.albumIDs[key] == nil {
            store.albumIDOrder.append(key)
        }
        store.albumIDs[key] = albumID ?? ""
        let excess = store.albumIDOrder.count - Self.albumIDLimit
        if excess > 0 {
            for old in store.albumIDOrder.prefix(excess) {
                store.albumIDs[old] = nil
            }
            store.albumIDOrder.removeFirst(excess)
        }
    }

    /// Writes the store a moment after the last change.
    private func save() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            let snapshot = store
            await CachesWriter.shared.write(snapshot, to: Self.fileName)
        }
    }

    private struct Entry: Codable, Sendable {
        let artwork: AppleMotionArtwork?
        let checkedAt: Date

        /// How long an album's video is believed.
        static let videoLifetime: TimeInterval = 30 * 24 * 60 * 60
        /// How long an album with no video is believed.
        static let noneLifetime: TimeInterval = 7 * 24 * 60 * 60

        var isExpired: Bool {
            let lifetime = artwork == nil ? Self.noneLifetime : Self.videoLifetime
            return Date.now.timeIntervalSince(checkedAt) > lifetime
        }
    }

    private struct Store: Codable, Sendable {
        /// Catalog album id to what it has.
        var albums: [String: Entry] = [:]
        /// A song's or library album's key, or an album's name, to its
        /// catalog album's id; empty for one with none.
        var albumIDs: [String: String] = [:]
        /// `albumIDs`' keys, oldest first.
        var albumIDOrder: [String] = []
    }
}
