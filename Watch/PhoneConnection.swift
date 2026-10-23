import Foundation
import OSLog
import WatchConnectivity
import WatchKit
import WatchSync

/// The watch's end of WatchConnectivity (`WatchSyncMessage`). From the
/// iPhone's application context it takes the sign-ins (to `WatchAccounts`),
/// the picks (merged into the download store's) and the places in the books
/// among them (merged into `WatchBookStore`'s). To the iPhone it sends its
/// own: the picks and places as the watch has them, when they change here.
/// While the app is open, what the iPhone plays comes as messages, to
/// `PhoneNowPlaying`, and its queue in answer to Up Next asking.
@MainActor
final class PhoneConnection {
    static let shared = PhoneConnection()

    private let relay = PhoneSessionRelay()
    private let logger = Logger(subsystem: "dance.cue.watch", category: "PhoneConnection")
    /// Picks or places changed before the session was up.
    private var hasPending = false
    /// When the sign-ins were last asked for, so a burst of downloads asks
    /// once.
    private var askedForCredentialsAt: Date?

    private init() {}

    func activate() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        relay.connection = self
        WCSession.default.delegate = relay
        WCSession.default.activate()
    }

    /// The picks and the places in the books among them, as they are now.
    func send() {
        guard WCSession.default.activationState == .activated else {
            hasPending = true
            return
        }
        let picks = WatchDownloadStore.shared.picks
        let places = WatchBookStore.shared.placesToShare
        do {
            try WCSession.default.updateApplicationContext(WatchSyncMessage.context(picks: picks, places: places))
        } catch {
            logger.error("Couldn't send the picks: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Asks the iPhone for its sign-ins now, for an Audiobookshelf token
    /// about to run out: the iPhone renews its own and answers with it. A
    /// minute apart at most, and only with the iPhone in reach (the system
    /// wakes Cue there to answer).
    func requestCredentials() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable,
              Date.now.timeIntervalSince(askedForCredentialsAt ?? .distantPast) > 60 else { return }
        askedForCredentialsAt = .now
        logger.info("Asking the iPhone for a fresh Audiobookshelf token")
        session.sendMessage(WatchSyncMessage.credentialsRequest, replyHandler: { @Sendable reply in
            let credentials = WatchSyncMessage.credentials(in: reply)
            Task { @MainActor in
                PhoneConnection.shared.didReceive(credentials: credentials, picks: nil, places: nil)
            }
        }, errorHandler: { @Sendable error in
            let message = error.localizedDescription
            Task { @MainActor in
                PhoneConnection.shared.logger.error("The iPhone didn't answer for its sign-ins: \(message, privacy: .public)")
            }
        })
    }

    /// Asks the iPhone what it plays, or to play or pause it; its answer is
    /// what it plays then. Or asks for its queue, which is the answer. Only
    /// with the iPhone in reach (the system wakes Cue there to answer).
    func askPhone(_ request: [String: Any]) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(request, replyHandler: { @Sendable reply in
            if let queue = WatchSyncMessage.queue(in: reply) {
                Task { @MainActor in
                    PhoneNowPlaying.shared.apply(queue: queue)
                }
            }
            guard WatchSyncMessage.carriesNowPlaying(reply) else { return }
            let nowPlaying = WatchSyncMessage.nowPlaying(in: reply)
            Task { @MainActor in
                PhoneNowPlaying.shared.apply(nowPlaying)
            }
        }, errorHandler: { @Sendable error in
            let message = error.localizedDescription
            Task { @MainActor in
                PhoneConnection.shared.logger.error("The iPhone didn't answer about what it plays: \(message, privacy: .public)")
                PhoneNowPlaying.shared.askFailed()
            }
        })
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

    /// Sends what waited for the session — as it is now, which may have
    /// merged in the iPhone's since.
    fileprivate func didActivate() {
        if hasPending {
            hasPending = false
            send()
        }
        PhoneNowPlaying.shared.reachabilityDidChange(WCSession.default.isReachable)
    }

    fileprivate func reachabilityDidChange(_ isReachable: Bool) {
        PhoneNowPlaying.shared.reachabilityDidChange(isReachable)
    }

    /// The iPhone's context: sign-ins first, so the picks that come with
    /// them are looked up with them; the places once the picks are in, so
    /// a book just picked takes its place.
    fileprivate func didReceive(credentials: WatchCredentials?, picks: WatchPicks?, places: WatchBookPlaces?) {
        let store = WatchDownloadStore.shared
        if let credentials {
            switch WatchAccounts.shared.apply(credentials) {
            case .signIns: store.credentialsDidChange()
            case .tokenRenewed: store.tokenDidRenew()
            case .none: break
            }
        }
        var tellPhone = false
        if let picks {
            tellPhone = store.apply(picks) || tellPhone
        }
        if let places {
            tellPhone = WatchBookStore.shared.apply(places) || tellPhone
        }
        if tellPhone {
            send()
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
        let places = WatchSyncMessage.places(in: context)
        Task { @MainActor in
            self.connection?.didReceive(credentials: credentials, picks: picks, places: places)
            self.connection?.didActivate()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let credentials = WatchSyncMessage.credentials(in: applicationContext)
        let picks = WatchSyncMessage.picks(in: applicationContext)
        let places = WatchSyncMessage.places(in: applicationContext)
        Task { @MainActor in
            self.connection?.didReceive(credentials: credentials, picks: picks, places: places)
        }
    }

    /// What the iPhone plays, sent as it changes while the app is open.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard WatchSyncMessage.carriesNowPlaying(message) else { return }
        let nowPlaying = WatchSyncMessage.nowPlaying(in: message)
        Task { @MainActor in
            PhoneNowPlaying.shared.apply(nowPlaying)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.connection?.reachabilityDidChange(reachable)
        }
    }
}
