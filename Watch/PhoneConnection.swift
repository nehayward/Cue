import Foundation
import OSLog
import WatchConnectivity
import WatchKit
import WatchSync

/// The watch's end of WatchConnectivity (`WatchSyncMessage`). From the
/// iPhone it takes the sign-ins (to `WatchAccounts`) and the library (to
/// the download store), from its application context, or a file when the
/// library is big. To the iPhone it sends its own application context: the
/// library as the watch has it — changed here when music is added from the
/// watch — and its status.
@MainActor
final class PhoneConnection {
    static let shared = PhoneConnection()

    private let relay = PhoneSessionRelay()
    private let logger = Logger(subsystem: "dance.cue.watch", category: "PhoneConnection")
    /// What to send once the session is up.
    private var pending: (status: WatchStatus, library: WatchLibrary)?
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

    /// Sends the status, and the library with it — as a file when it's too
    /// big for the context, in place of any older one still waiting to go.
    func send(status: WatchStatus, library: WatchLibrary) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            pending = (status, library)
            return
        }
        let libraryFits: Bool
        do {
            let (context, fits) = try WatchSyncMessage.context(library: library, status: status)
            try session.updateApplicationContext(context)
            libraryFits = fits
        } catch {
            logger.error("Couldn't send the status: \(error.localizedDescription, privacy: .public)")
            libraryFits = false
        }
        guard !libraryFits, library.revision > 0 else { return }
        for transfer in session.outstandingFileTransfers where WatchSyncMessage.isLibrary(transfer.file.metadata) {
            transfer.cancel()
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Outgoing", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        let url = directory.appendingPathComponent("library-\(library.revision).json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try library.encoded().write(to: url, options: .atomic)
            session.transferFile(url, metadata: WatchSyncMessage.libraryMetadata(revision: library.revision))
        } catch {
            logger.error("Couldn't send the library: \(error.localizedDescription, privacy: .public)")
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
        if let pending {
            self.pending = nil
            send(status: pending.status, library: pending.library)
        } else {
            // So the iPhone hears from a freshly installed watch app, and
            // sends its library if this one is behind.
            WatchDownloadStore.shared.postStatusNow()
        }
        completeConnectivityTasksIfDone()
    }

    /// The iPhone's context: sign-ins first, so a library that follows can
    /// be fetched with them.
    fileprivate func didReceive(credentials: WatchCredentials?, library: WatchLibrary?) {
        if let credentials {
            WatchAccounts.shared.apply(credentials)
        }
        if let library {
            WatchDownloadStore.shared.apply(library)
        }
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

    /// Takes the latest the iPhone left, in case it came while the app
    /// wasn't running, then reports.
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let credentials = WatchSyncMessage.credentials(in: context)
        let library = WatchSyncMessage.library(in: context)
        Task { @MainActor in
            self.connection?.didReceive(credentials: credentials, library: library)
            self.connection?.didActivate()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let credentials = WatchSyncMessage.credentials(in: applicationContext)
        let library = WatchSyncMessage.library(in: applicationContext)
        Task { @MainActor in
            self.connection?.didReceive(credentials: credentials, library: library)
        }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard WatchSyncMessage.isLibrary(file.metadata) else { return }
        // Read now: the system deletes the file when this returns.
        guard let data = try? Data(contentsOf: file.fileURL),
              let library = try? WatchLibrary.decoded(from: data) else { return }
        Task { @MainActor in
            self.connection?.didReceive(credentials: nil, library: library)
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }
}
