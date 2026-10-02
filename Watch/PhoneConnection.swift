import Foundation
import Observation
import OSLog
import WatchConnectivity
import WatchKit
import WatchSync

/// The watch's end of WatchConnectivity (`WatchSyncMessage`). From the
/// iPhone's application context it takes the sign-ins (to `WatchAccounts`)
/// and the picks (merged into the download store's). To the iPhone it sends
/// its own: the picks as the watch has them, when they change here, and
/// songs to play there (`play(_:)`) while it's in reach.
@MainActor
@Observable
final class PhoneConnection {
    static let shared = PhoneConnection()

    /// The iPhone can be sent something to play: in reach, with Cue on it.
    private(set) var isPhoneReachable = false

    @ObservationIgnored private let relay = PhoneSessionRelay()
    @ObservationIgnored private let logger = Logger(subsystem: "dance.cue.watch", category: "PhoneConnection")
    /// Picks changed before the session was up.
    @ObservationIgnored private var hasPending = false

    private init() {}

    func activate() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        relay.connection = self
        WCSession.default.delegate = relay
        WCSession.default.activate()
    }

    func send(picks: WatchPicks) {
        guard WCSession.default.activationState == .activated else {
            hasPending = true
            return
        }
        do {
            try WCSession.default.updateApplicationContext(WatchSyncMessage.context(picks: picks))
        } catch {
            logger.error("Couldn't send the picks: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Hands these songs to Cue on the iPhone, which plays them wherever
    /// it's pointed — the phone or its Sonos speakers — from `startIndex`.
    /// The message wakes Cue there; the reply says where it's playing, or
    /// why it isn't.
    func play(_ request: WatchPlayRequest) async -> WatchPlayReply {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            return .failed("Your iPhone isn't in reach.")
        }
        let data: Data
        do {
            data = try WatchSyncMessage.requestData(request)
        } catch {
            return .failed("Couldn't send the songs to your iPhone.")
        }
        let reply = await Self.send(data, logger: logger)
        if let playingOn = reply.playingOn {
            logger.notice("Playing on \(playingOn, privacy: .public) from the watch")
        }
        return reply
    }

    /// Off the main actor: WatchConnectivity answers on a queue of its own.
    private nonisolated static func send(_ data: Data, logger: Logger) async -> WatchPlayReply {
        await withCheckedContinuation { continuation in
            WCSession.default.sendMessageData(data) { reply in
                continuation.resume(returning: WatchSyncMessage.playReply(in: reply) ?? .failed("Your iPhone didn't answer."))
            } errorHandler: { error in
                logger.error("Couldn't play on the iPhone: \(error.localizedDescription, privacy: .public)")
                continuation.resume(returning: .failed("Couldn't reach Cue on your iPhone. Open it there and try again."))
            }
        }
    }

    /// Keeps a WatchConnectivity wake open until what the iPhone sent has
    /// arrived and been looked up — or 20 seconds, past which the system
    /// would end it anyway.
    func hold(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        activate()
        Task { @MainActor in
            let deadline = Date.now.addingTimeInterval(20)
            while Date.now < deadline {
                let session = WCSession.default
                let settled = session.activationState == .activated && !session.hasContentPending
                if settled, WatchDownloadStore.shared.lookingUp.isEmpty { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            task.setTaskCompletedWithSnapshot(false)
        }
    }

    /// Sends what waited for the session — as the picks are now, which
    /// may have merged in the iPhone's since.
    fileprivate func didActivate() {
        reachabilityDidChange()
        if hasPending {
            hasPending = false
            send(picks: WatchDownloadStore.shared.picks)
        }
    }

    fileprivate func reachabilityDidChange() {
        let session = WCSession.default
        isPhoneReachable = session.activationState == .activated && session.isReachable && session.isCompanionAppInstalled
    }

    /// The iPhone's context: sign-ins first, so the picks that come with
    /// them are looked up with them.
    fileprivate func didReceive(credentials: WatchCredentials?, picks: WatchPicks?) {
        let store = WatchDownloadStore.shared
        if let credentials, WatchAccounts.shared.apply(credentials) {
            store.credentialsDidChange()
        }
        if let picks {
            store.apply(picks)
        }
    }
}

/// The session's delegate, off the main actor: WatchConnectivity calls it
/// on its own queue.
private final class PhoneSessionRelay: NSObject, WCSessionDelegate, @unchecked Sendable {
    weak var connection: PhoneConnection?

    /// Takes the latest the iPhone left, in case it came while the app
    /// wasn't running.
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let credentials = WatchSyncMessage.credentials(in: context)
        let picks = WatchSyncMessage.picks(in: context)
        Task { @MainActor in
            self.connection?.didReceive(credentials: credentials, picks: picks)
            self.connection?.didActivate()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let credentials = WatchSyncMessage.credentials(in: applicationContext)
        let picks = WatchSyncMessage.picks(in: applicationContext)
        Task { @MainActor in
            self.connection?.didReceive(credentials: credentials, picks: picks)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.connection?.reachabilityDidChange()
        }
    }
}
