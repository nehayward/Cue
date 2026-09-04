import Foundation
import SonosKit

#if canImport(BackgroundTasks) && !os(visionOS)
import BackgroundTasks

/// Keeps a batch of downloads going, and visible, after the app leaves the
/// foreground: a `BGContinuedProcessingTask` submitted from the user's tap.
/// The system shows its title and progress in a Live Activity, where the
/// person can also cancel it, and keeps the app running to drive it.
///
/// The transfer itself still belongs to the background `URLSession` (for
/// Plex and Subsonic) or to iCloud (for the Files folder) — both carry on
/// even if this task is ended. What the task adds is the app staying awake
/// to run them at full speed, live progress on the Lock Screen, and one
/// place to cancel. One batch runs at a time; downloads queued while it
/// runs join it.
@MainActor
final class ContinuedDownloadTask {
    static let shared = ContinuedDownloadTask()

    /// Registered in Info.plist under `BGTaskSchedulerPermittedIdentifiers`.
    static var identifier: String {
        (Bundle.main.bundleIdentifier ?? "dance.cue") + ".downloads"
    }

    private final class Batch {
        var title: String
        var keys: Set<String>
        var cloudTrackIDs: Set<String>
        var task: BGContinuedProcessingTask?
        var expired = false

        init(title: String, keys: Set<String>, cloudTrackIDs: Set<String>) {
            self.title = title
            self.keys = keys
            self.cloudTrackIDs = cloudTrackIDs
        }

        var total: Int { keys.count + cloudTrackIDs.count }
    }

    private var registered = false
    private var current: Batch?

    /// Registers the launch handler. Cheap, idempotent, and required
    /// before a submission; the app delegate calls it at launch.
    func register() {
        guard !registered, #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        registered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: nil) { [weak self] task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                self?.run(task)
            }
        }
    }

    /// Follows download-manager entries until they settle.
    func track(downloadKeys keys: [String], title: String) {
        add(keys: Set(keys), cloud: [], title: title)
    }

    /// Follows Files songs until iCloud has them on the device.
    func track(cloudTrackIDs ids: [String], title: String) {
        add(keys: [], cloud: Set(ids), title: title)
    }

    private func add(keys: Set<String>, cloud: Set<String>, title: String) {
        guard !keys.isEmpty || !cloud.isEmpty else { return }
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }

        if let current, !current.expired {
            // Joining the running batch: more to do, same Live Activity.
            current.keys.formUnion(keys)
            current.cloudTrackIDs.formUnion(cloud)
            if let task = current.task {
                task.progress.totalUnitCount = Int64(max(1, current.total) * 100)
                task.updateTitle(current.title, subtitle: measure(current).subtitle)
            }
            return
        }

        register()
        let batch = Batch(title: title, keys: keys, cloudTrackIDs: cloud)
        current = batch

        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.identifier,
            title: title,
            subtitle: "Starting…"
        )
        // Queue rather than fail: if the system is busy the task waits its
        // turn, and the transfers are already under way regardless.
        request.strategy = .queue
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // No Live Activity, but nothing lost: the background session and
            // iCloud carry the downloads on their own.
            print("Continued download task not accepted: \(error)")
            current = nil
        }
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    private func run(_ task: BGContinuedProcessingTask) {
        guard let batch = current, batch.task == nil else {
            task.setTaskCompleted(success: false)
            return
        }
        batch.task = task
        task.progress.totalUnitCount = Int64(max(1, batch.total) * 100)
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.expire(batch)
            }
        }
        Task { @MainActor [weak self] in
            await self?.drive(task, batch: batch)
        }
    }

    /// The person cancelled from the Live Activity, or the system ran out
    /// of room for the task. Either way the in-flight server downloads
    /// pause — resume data kept, one tap in Downloads to continue — rather
    /// than run on invisibly. iCloud transfers can't be stopped from here;
    /// they simply finish on their own.
    private func expire(_ batch: Batch) {
        batch.expired = true
        for key in batch.keys {
            DownloadManager.shared.pause(key: key)
        }
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    private func drive(_ task: BGContinuedProcessingTask, batch: Batch) async {
        if !batch.cloudTrackIDs.isEmpty {
            FilesLibraryService.shared.startCloudMonitor()
        }
        var settled = false
        while !batch.expired {
            let reading = measure(batch)
            // Progress is what the system judges the task by: a task that
            // reports none is the first to go when resources run short.
            task.progress.completedUnitCount = reading.units
            task.updateTitle(batch.title, subtitle: reading.subtitle)
            if reading.settled == batch.total {
                settled = true
                break
            }
            try? await Task.sleep(for: .seconds(1))
        }
        if current === batch {
            current = nil
        }
        task.setTaskCompleted(success: settled && !batch.expired)
    }

    private struct Reading {
        var settled = 0
        var units: Int64 = 0
        var subtitle = ""
    }

    /// Where the batch stands, from the manager's entries and the folder's
    /// iCloud status. A download that was cancelled or removed counts as
    /// settled; a paused or failed one does too, since it won't move again
    /// without the person's say-so.
    private func measure(_ batch: Batch) -> Reading {
        let manager = DownloadManager.shared
        let files = FilesLibraryService.shared
        var reading = Reading()
        var completed = 0
        var failed = 0
        var received: Int64 = 0
        var expected: Int64 = 0

        for key in batch.keys {
            guard let item = manager.items[key] else {
                reading.settled += 1
                reading.units += 100
                continue
            }
            switch item.state {
            case .completed:
                reading.settled += 1
                completed += 1
                reading.units += 100
                received += item.fileSize ?? item.bytesExpected
                expected += item.fileSize ?? item.bytesExpected
            case .failed, .paused:
                reading.settled += 1
                failed += 1
                reading.units += 100
            case .queued, .downloading:
                reading.units += Int64(item.progress * 100)
                received += item.bytesReceived
                expected += item.bytesExpected
            }
        }

        for id in batch.cloudTrackIDs {
            switch files.cloudStatus(trackID: id) {
            case .local, .notCloud:
                reading.settled += 1
                completed += 1
                reading.units += 100
            case let .downloading(fraction):
                reading.units += Int64((fraction ?? 0) * 100)
            case .notDownloaded:
                break
            }
        }

        var parts = ["\(completed) of \(batch.total) songs"]
        if expected > 0 {
            let done = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
            let all = ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)
            parts.append("\(done) of \(all)")
        }
        if failed > 0 {
            parts.append(failed == 1 ? "1 stopped" : "\(failed) stopped")
        }
        reading.subtitle = parts.joined(separator: " • ")
        return reading
    }
}

#else

/// No continued processing on this platform; downloads still run on the
/// background session and iCloud, just without the system's progress card.
@MainActor
final class ContinuedDownloadTask {
    static let shared = ContinuedDownloadTask()
    func register() {}
    func track(downloadKeys keys: [String], title: String) {}
    func track(cloudTrackIDs ids: [String], title: String) {}
}

#endif
