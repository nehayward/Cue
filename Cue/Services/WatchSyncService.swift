import Defaults
import Foundation
import MusicSearchKit
import Observation
import OSLog
import SonosKit
import WatchSync
#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
import WatchConnectivity
#endif

/// Tells the Apple Watch what to put on itself, and how to reach it — and
/// plays what the watch hands over (Play On ▸ iPhone, `play(_:)`).
///
/// The watch is the client: it browses Plex and Subsonic itself, looks
/// songs up and downloads them (MusicSearchKit). All this iPhone sends is a
/// list of picks — albums, playlists, artists and songs by id
/// (`WatchPicks`) — and its Plex and Subsonic sign-ins (`WatchCredentials`),
/// as application context. The watch changes the picks too, from its own
/// browsing, and sends them back; each side merges what the other sends
/// (`WatchPicks.merged`), so neither loses the other's changes.
///
/// Only Plex and Subsonic, as with the download manager: their songs are
/// plain URLs the watch can fetch. Apple Music on the watch is the Music
/// app's (MusicKit has no player on watchOS).
///
/// Inert where there's no watch to pair (iPad, Mac, Vision Pro): nothing
/// is available, so no menu offers it.
@MainActor
@Observable
final class WatchSyncService {
    static let shared = WatchSyncService()

    private(set) var picks: WatchPicks
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false

    /// A watch is paired and has Cue on it, so music can be put there.
    var isAvailable: Bool { isPaired && isWatchAppInstalled }

    @ObservationIgnored private let logger = Logger(subsystem: "dance.cue", category: "WatchSync")
    /// The session's delegate, kept alive here; nil where there's no
    /// WatchConnectivity.
    @ObservationIgnored private var relay: AnyObject?
    /// The sign-ins last sent, so signing in or out, or a new server, goes
    /// across too.
    @ObservationIgnored private var sentCredentials: WatchCredentials?
    @ObservationIgnored private var foregroundObserver: NSObjectProtocol?

    private init() {
        picks = (try? Data(contentsOf: Self.picksURL)).flatMap { try? WatchPicks.decoded(from: $0) } ?? .empty
    }

    /// Starts the session, once, at launch.
    func activate() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard WCSession.isSupported(), relay == nil else { return }
        let relay = WatchSessionRelay()
        relay.service = self
        self.relay = relay
        WCSession.default.delegate = relay
        WCSession.default.activate()
        // Sign-ins change in Settings; coming back to Cue is when to check.
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.currentCredentials() != self.sentCredentials else { return }
                self.send()
            }
        }
        #endif
    }

    // MARK: - Picks

    /// Whether this can go on the watch: a Plex or Subsonic song with its
    /// stream, or an album, playlist or artist of them — what the download
    /// manager takes — and a watch with Cue to put it on.
    func canAdd(_ item: PlayableContent) -> Bool {
        guard isAvailable else { return false }
        let downloads = DownloadManager.shared
        return item.content.type == .track ? downloads.canDownload(item) : downloads.canDownload(contentsOf: item)
    }

    func isOnWatch(_ item: PlayableContent) -> Bool {
        Self.pick(for: item).map { picks.contains(key: $0.key) } ?? false
    }

    func add(_ item: PlayableContent) {
        guard canAdd(item), let pick = Self.pick(for: item) else { return }
        picks.add(pick)
        picksDidChange()
    }

    func remove(_ item: PlayableContent) {
        guard let pick = Self.pick(for: item) else { return }
        remove(key: pick.key)
    }

    func remove(key: String) {
        picks.remove(key: key)
        picksDidChange()
    }

    func removeAll() {
        picks.removeAll()
        picksDidChange()
    }

    private func picksDidChange() {
        save()
        send()
    }

    /// An album, playlist, artist or song as the watch looks it up: by the
    /// id this iPhone's library gives it.
    static func pick(for item: PlayableContent) -> WatchPick? {
        guard let source = WatchSource(item.content.service) else { return nil }
        let kind: WatchPick.Kind
        switch item.content.type {
        case .track: kind = .song
        case .album: kind = .album
        case .playlist: kind = .playlist
        case .artist: kind = .artist
        default: return nil
        }
        return WatchPick(
            source: source,
            kind: kind,
            id: item.content.id,
            title: item.title,
            subtitle: item.metadata?.artist ?? item.subtitle,
            artworkURL: item.thumbnail ?? item.artwork
        )
    }

    // MARK: - Session

    /// This iPhone's Plex and Subsonic sign-ins, as MusicSearchKit keeps them.
    private func currentCredentials() -> WatchCredentials {
        var credentials = WatchCredentials()
        if let token = PlexAuthenticator.shared.authToken, !token.isEmpty {
            let plex = PlexAPI.shared
            credentials.plex = .init(
                token: token,
                serverID: plex.serverID,
                librarySectionID: plex.librarySelectionID,
                connectionPreference: plex.connectionPreference.rawValue
            )
        }
        let subsonic = SubsonicAPI.shared
        if subsonic.isConfigured {
            credentials.subsonic = .init(serverAddress: subsonic.serverAddress, username: subsonic.username, password: subsonic.password)
        }
        return credentials
    }

    /// The picks and the sign-ins, as application context: only the latest
    /// matters, and it reaches a watch app that isn't running.
    private func send() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard WCSession.default.activationState == .activated, isAvailable else { return }
        let credentials = currentCredentials()
        do {
            try WCSession.default.updateApplicationContext(WatchSyncMessage.context(picks: picks, credentials: credentials))
            sentCredentials = credentials
        } catch {
            logger.error("Couldn't send to the watch: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    fileprivate func sessionStateDidChange(isPaired: Bool, isWatchAppInstalled: Bool) {
        self.isPaired = isPaired
        self.isWatchAppInstalled = isWatchAppInstalled
        // A watch newly paired or with Cue newly on it hasn't heard yet.
        send()
    }

    /// The watch's picks, merged in. When the watch was missing something
    /// of ours, it hears back.
    fileprivate func didReceive(picks theirs: WatchPicks) {
        let merged = picks.merged(with: theirs)
        if merged != picks {
            picks = merged
            save()
        }
        if merged != theirs {
            send()
        }
    }

    // MARK: - Play from the watch

    #if os(iOS) && !targetEnvironment(macCatalyst)
    /// Songs the watch handed over, played wherever this iPhone is pointed:
    /// the phone, or the Sonos group it's set to (the phone while offline).
    /// Answers once the song it starts at is playing. A speaker gets that
    /// one first and the rest after: the songs after it, then the ones
    /// before it in front. That's one call a song, and the message may have
    /// woken Cue in the background, so a background task keeps it running
    /// meanwhile; past the system's time, a long list may land part-way.
    fileprivate func play(_ request: WatchPlayRequest) async -> WatchPlayReply {
        let tracks = request.songs.map(Self.playable(for:))
        let start = request.startIndex
        guard tracks.indices.contains(start) else { return .failed("There was nothing to play.") }
        let background = WakeTask.begin("Play from Apple Watch")
        let sonos = SonosService.shared
        let destination = sonos.isEnabled ? (PlayDestination.remembered ?? .device) : .device
        logger.notice("watch play: \(tracks.count) songs from \(start), destination=\(String(describing: destination), privacy: .public)")

        if !OfflineMode.shared.isActive, let id = destination.groupID {
            // Woken by the watch, Cue may not have found the speakers yet.
            if sonos.groups.isEmpty {
                try? await sonos.updateGroups()
            }
            guard let group = sonos.groups.first(where: { $0.coordinatorID == id }) else {
                background.end()
                return .failed("The speakers Cue on your iPhone plays on can't be found. Pick others there, or play on this watch.")
            }
            // Playing on the speaker takes over from the phone, as a Play
            // there does (`PlayDestinationRouter`).
            LocalPlaybackService.shared.park()
            do {
                try await sonos.queue(contents: [tracks[start]], group: group, position: .replace, startIndex: 0)
            } catch {
                background.end()
                logger.error("watch play on \(group.nameWithCount, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return .failed("\(group.nameWithCount) couldn't play it: \(error.localizedDescription)")
            }
            let after = Array(tracks[(start + 1)...])
            // Each goes in at the top, so they're handed over last first.
            let before = Array(tracks[..<start].reversed())
            Task {
                defer { background.end() }
                if !after.isEmpty {
                    try? await sonos.queue(contents: after, group: group, position: .end)
                }
                if !before.isEmpty {
                    try? await sonos.queue(contents: before, group: group, position: .front)
                }
            }
            record(tracks[start])
            return WatchPlayReply(playingOn: group.nameWithCount)
        }

        defer { background.end() }
        let player = LocalPlaybackService.shared
        do {
            try await player.play(tracks, startingAt: start)
        } catch {
            logger.error("watch play on the phone failed: \(error.localizedDescription, privacy: .public)")
            return .failed("Your iPhone couldn't play it. Open Cue there and try again.")
        }
        // Woken in the background while another app plays, iOS can refuse
        // Cue the audio session, and the player says nothing of it. Not
        // playing after a few seconds, it didn't start.
        for _ in 0 ..< 16 where !player.isPlaying {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard player.isPlaying else {
            logger.error("watch play on the phone didn't start")
            return .failed("Your iPhone didn't start playing. Open Cue there and try again.")
        }
        record(tracks[start])
        return WatchPlayReply(playingOn: "iPhone")
    }

    /// Into Recently Played, as a play from the phone.
    private func record(_ track: PlayableContent) {
        let history = PlayHistoryService.shared
        history.history.remove(track)
        history.history.insert(track, at: 0)
    }

    /// A song from the watch as this iPhone plays it: a speaker by its id,
    /// the phone from its stream — the whole song off the server, as the
    /// iPhone's own Plex and Subsonic songs carry it. A Subsonic stream is
    /// built again with this iPhone's sign-in; a Plex one names the file
    /// on the server, which only the watch's lookup knows.
    private static func playable(for song: WatchPlayRequest.Song) -> PlayableContent {
        let service: MusicService
        let stream: URL
        switch song.source {
        case .plex:
            service = .plex
            stream = song.streamURL
        case .subsonic:
            service = .subsonic
            stream = SubsonicAPI.streamURL(for: song.id, fileExtension: song.audioCodec) ?? song.streamURL
        }
        return PlayableContent(
            title: song.title,
            subtitle: song.artist,
            thumbnail: song.artworkURL,
            artwork: largeArtwork(song.artworkURL),
            content: MediaContent(service: service, id: song.id, type: .track, location: nil),
            previewURL: stream,
            metadata: PlayableContentMetadata(
                duration: song.duration.map { Duration.seconds($0) },
                artist: song.artist,
                album: song.album,
                audioCodec: song.audioCodec
            )
        )
    }

    /// The watch asks its servers for small covers; the phone's player
    /// draws them large. The same cover at the size the iPhone uses: a
    /// Plex transcode's width and height, a Subsonic cover's size.
    private static func largeArtwork(_ url: URL?) -> URL? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let names: Set<String>
        let size: Int
        if components.path.hasSuffix("/photo/:/transcode") {
            names = ["width", "height"]
            size = PlexImageSize.artwork
        } else if components.path.hasSuffix("getCoverArt") || components.path.hasSuffix("getCoverArt.view") {
            names = ["size"]
            size = SubsonicAPI.artworkSize
        } else {
            return url
        }
        components.queryItems = components.queryItems?.map { item in
            names.contains(item.name) ? URLQueryItem(name: item.name, value: "\(size)") : item
        }
        return components.url ?? url
    }
    #endif

    // MARK: - Storage

    private static var picksURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("AppleWatch/picks.json")
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.picksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try picks.encoded().write(to: Self.picksURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.error("Couldn't save the watch picks: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
/// The session's delegate, off the main actor because WatchConnectivity
/// calls it on its own queue; everything it hears goes to the service.
private final class WatchSessionRelay: NSObject, WCSessionDelegate, @unchecked Sendable {
    weak var service: WatchSyncService?

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        let picks = WatchSyncMessage.picks(in: session.receivedApplicationContext)
        Task { @MainActor in
            if let picks { self.service?.didReceive(picks: picks) }
            self.service?.sessionStateDidChange(isPaired: paired, isWatchAppInstalled: installed)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to another watch: activate again for the new one.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor in
            self.service?.sessionStateDidChange(isPaired: paired, isWatchAppInstalled: installed)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let picks = WatchSyncMessage.picks(in: applicationContext) else { return }
        Task { @MainActor in
            self.service?.didReceive(picks: picks)
        }
    }

    /// Songs to play here, from the watch's Play On ▸ iPhone.
    func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        guard let request = WatchSyncMessage.playRequest(in: messageData) else {
            replyHandler(WatchSyncMessage.replyData(.failed("Update Cue on your iPhone to play from the watch.")))
            return
        }
        Task { @MainActor in
            let reply = await self.service?.play(request) ?? .failed("Open Cue on your iPhone and try again.")
            replyHandler(WatchSyncMessage.replyData(reply))
        }
    }
}

/// Keeps Cue running, when the watch woke it in the background, until
/// what it was woken for is under way — or the system's time is up.
@MainActor
private final class WakeTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    static func begin(_ name: String) -> WakeTask {
        let task = WakeTask()
        task.id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak task] in
            task?.end()
        }
        return task
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
#endif

extension WatchSource {
    init?(_ service: MusicService) {
        switch service {
        case .plex: self = .plex
        case .subsonic: self = .subsonic
        default: return nil
        }
    }
}
