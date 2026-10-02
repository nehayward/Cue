import Foundation
import OSLog
import WatchConnectivity
import WatchKit
import WatchSync

/// The watch's end of WatchConnectivity (`WatchSyncMessage`). From the
/// iPhone's application context it takes the sign-ins (to `WatchAccounts`)
/// and the picks (merged into the download store's). To the iPhone it sends
/// its own: the picks as the watch has them, when they change here.
@MainActor
final class PhoneConnection {
    static let shared = PhoneConnection()

    private let relay = PhoneSessionRelay()
    private let logger = Logger(subsystem: "dance.cue.watch", category: "PhoneConnection")
    /// What to send once the session is up.
    private var pending: WatchPicks?

    private init() {}

    func activate() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        relay.connection = self
        WCSession.default.delegate = relay
        WCSession.default.activate()
    }

    func send(picks: WatchPicks) {
        guard WCSession.default.activationState == .activated else {
            pending = picks
            return
        }
        do {
            try WCSession.default.updateApplicationContext(WatchSyncMessage.context(picks: picks))
        } catch {
            logger.error("Couldn't send the picks: \(error.localizedDescription, privacy: .public)")
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

    fileprivate func didActivate() {
        if let pending {
            self.pending = nil
            send(picks: pending)
        }
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
}
