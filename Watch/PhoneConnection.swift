import Foundation
import OSLog
import WatchConnectivity
import WatchKit
import WatchSync

/// The watch's end of WatchConnectivity: takes the library the iPhone
/// sends (application context, or a file when it's big — see
/// `WatchSyncMessage`) to the download store, and sends the store's status
/// back as application context.
@MainActor
final class PhoneConnection {
    static let shared = PhoneConnection()

    private let relay = PhoneSessionRelay()
    private let logger = Logger(subsystem: "dance.cue.watch", category: "PhoneConnection")
    /// A status to send once the session is up.
    private var pendingStatus: WatchStatus?
    /// Background wakes for WatchConnectivity, held until what the iPhone
    /// sent has been delivered.
    private var connectivityTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private var pendingObservation: NSKeyValueObservation?

    private init() {}

    func activate() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        relay.connection = self
        WCSession.default.delegate = relay
        pendingObservation = WCSession.default.observe(\.hasContentPending) { [weak self] _, _ in
            Task { @MainActor in self?.completeConnectivityTasksIfDone() }
        }
        WCSession.default.activate()
    }

    func send(_ status: WatchStatus) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            pendingStatus = status
            return
        }
        do {
            try session.updateApplicationContext(WatchSyncMessage.statusContext(status))
        } catch {
            logger.error("Couldn't send the status: \(error.localizedDescription, privacy: .public)")
        }
    }

    enum RequestError: LocalizedError {
        case notConnected
        case unreadableReply

        var errorDescription: String? {
            switch self {
            case .notConnected: "Your iPhone isn't connected. Keep it nearby with Cue installed."
            case .unreadableReply: "Your iPhone sent something this watch can't read. Update Cue on both."
            }
        }
    }

    /// Asks the iPhone (`WatchBrowseServer`) and waits for its answer.
    /// WatchConnectivity wakes Cue there if it isn't running; the iPhone
    /// has to be in reach — over Bluetooth, or the same Wi‑Fi.
    func request(_ request: WatchRequest) async throws -> WatchReply {
        activate()
        let session = WCSession.default
        guard session.activationState == .activated else { throw RequestError.notConnected }
        let data = try request.encoded()
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessageData(data, replyHandler: { reply in
                if let decoded = try? WatchReply.decoded(from: reply) {
                    continuation.resume(returning: decoded)
                } else {
                    continuation.resume(throwing: RequestError.unreadableReply)
                }
            }, errorHandler: { error in
                let code = (error as NSError).domain == WCErrorDomain ? WCError.Code(rawValue: (error as NSError).code) : nil
                switch code {
                case .notReachable, .deviceNotPaired, .companionAppNotInstalled:
                    continuation.resume(throwing: RequestError.notConnected)
                default:
                    continuation.resume(throwing: error)
                }
            })
        }
    }

    /// Keeps a WatchConnectivity wake open until the session has handed
    /// over everything waiting — or 20 seconds, past which the system would
    /// end it anyway.
    func hold(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        activate()
        connectivityTasks.append(task)
        completeConnectivityTasksIfDone()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, let index = self.connectivityTasks.firstIndex(where: { $0 === task }) else { return }
            self.connectivityTasks.remove(at: index)
            task.setTaskCompletedWithSnapshot(false)
        }
    }

    fileprivate func didActivate() {
        if let pendingStatus {
            self.pendingStatus = nil
            send(pendingStatus)
        } else {
            // So the iPhone hears from a freshly installed watch app, and
            // sends its library if this one is behind.
            WatchDownloadStore.shared.postStatusNow()
        }
        completeConnectivityTasksIfDone()
    }

    fileprivate func didReceive(_ library: WatchLibrary) {
        WatchDownloadStore.shared.apply(library)
        completeConnectivityTasksIfDone()
    }

    private func completeConnectivityTasksIfDone() {
        let session = WCSession.default
        guard !connectivityTasks.isEmpty, session.activationState == .activated, !session.hasContentPending else { return }
        let tasks = connectivityTasks
        connectivityTasks = []
        tasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
    }
}

/// The session's delegate, off the main actor: WatchConnectivity calls it
/// on its own queue.
private final class PhoneSessionRelay: NSObject, WCSessionDelegate, @unchecked Sendable {
    weak var connection: PhoneConnection?

    /// Takes the latest library the iPhone left, in case it came while
    /// the app wasn't running, then reports.
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let library = WatchSyncMessage.library(in: session.receivedApplicationContext)
        Task { @MainActor in
            if let library {
                self.connection?.didReceive(library)
            }
            self.connection?.didActivate()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let library = WatchSyncMessage.library(in: applicationContext) else { return }
        Task { @MainActor in
            self.connection?.didReceive(library)
        }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard WatchSyncMessage.isLibrary(file.metadata) else { return }
        // Read now: the system deletes the file when this returns.
        guard let data = try? Data(contentsOf: file.fileURL),
              let library = try? WatchLibrary.decoded(from: data) else { return }
        Task { @MainActor in
            self.connection?.didReceive(library)
        }
    }
}
