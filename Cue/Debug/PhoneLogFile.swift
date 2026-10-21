#if DEBUG && os(iOS)
import AVFoundation
import Foundation
import OSLog
import UIKit

/// Cue's own log as files in its container, so the Mac can copy it off the
/// phone with no password (a device's system log takes `sudo log collect`)
/// and no one at the phone:
///
///     xcrun devicectl device copy from --device <udid> \
///       --domain-type appDataContainer --domain-identifier dance.cue \
///       --source Library/Logs/Cue --destination build/phone-logs
///
/// Every `dance.cue` message of the launch, AVFoundation's errors (a stream
/// it gave up on says why only there) and the requests that failed
/// inside Cue (`Writer.source(of:)`), appended every 20 s while Cue
/// runs — in the car too — as it leaves the foreground, and just after a
/// player error, which in the background may be all Cue runs for. A file a launch,
/// named for when it started; the newest five are kept. Debug builds only.
enum PhoneLogFile {
    private static let queue = DispatchQueue(label: "dance.cue.phoneLogFile", qos: .utility)
    private static let interval: TimeInterval = 20
    private static let kept = 5

    /// Where the files go: Library/Logs/Cue.
    static var directory: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appending(path: "Logs/Cue", directoryHint: .isDirectory)
    }

    /// Starts writing this launch's file. Once, at launch.
    @MainActor
    static func start() {
        guard let directory else { return }
        let launched = Date.now
        let name = launched.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).dateTimeSeparator(.space))
            .replacingOccurrences(of: ":", with: "-")
        let file = directory.appending(path: "Cue \(name).log")
        let writer = Writer(file: file, since: launched)
        queue.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            prune(directory)
        }
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            queue.async { writer.append() }
        }
        // Leaving the foreground, iOS suspends Cue moments later unless it's
        // playing: the write asks for the time to finish, or what was logged
        // since the last one waits for Cue to come back.
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { writeHoldingTheApp(writer) }
        }
        // A player that fails in the background — a play from CarPlay or
        // the Lock Screen that doesn't start — leaves Cue nothing to keep it
        // running, so it's written a moment after, once the failure's own
        // lines are in. One such write at a time: a struggling stream logs
        // an error entry for every stall, and each would read the log
        // store again.
        for name in [AVPlayerItem.newErrorLogEntryNotification, AVPlayerItem.failedToPlayToEndTimeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    guard !errorWritePending else { return }
                    errorWritePending = true
                    writeHoldingTheApp(writer, after: 1) { errorWritePending = false }
                }
            }
        }
    }

    /// A write for a player error is on its way.
    @MainActor private static var errorWritePending = false

    /// Writes with time asked of iOS to finish, `after` seconds from now,
    /// then `done` on the main thread.
    @MainActor
    private static func writeHoldingTheApp(_ writer: Writer, after delay: TimeInterval = 0, done: @escaping @MainActor () -> Void = {}) {
        let task = BackgroundTask(name: "Cue log")
        queue.asyncAfter(deadline: .now() + delay) {
            writer.append()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    task.end()
                    done()
                }
            }
        }
    }

    /// Time asked of iOS, given back once: when the work is done, or when
    /// iOS runs out of patience first, whichever comes first.
    @MainActor
    private final class BackgroundTask {
        private var id = UIBackgroundTaskIdentifier.invalid

        init(name: String) {
            id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
                MainActor.assumeIsolated { self?.end() }
            }
        }

        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }

    /// Keeps the newest `kept` files.
    private static func prune(_ directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for old in files.filter({ $0.pathExtension == "log" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(kept) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    /// Appends what was logged since the last write. Used on `queue` only.
    ///
    /// Each pass reads back over the last `overlap` seconds too: a message
    /// can reach the store after a later one from another thread, and a
    /// pass that moved on past it would never write it. What's already in
    /// the file is remembered by time and text, and not written twice.
    private final class Writer: @unchecked Sendable {
        let file: URL
        var since: Date
        /// The messages written within `overlap` of the newest, by time and
        /// text.
        var written: [String: Date] = [:]

        private static let overlap: TimeInterval = 60

        init(file: URL, since: Date) {
            self.file = file
            self.since = since
        }

        func append() {
            let from = since.addingTimeInterval(-Self.overlap)
            guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
                  let entries = try? store.getEntries(at: store.position(date: from)) else { return }
            var text = ""
            var last = since
            for case let entry as OSLogEntryLog in entries where entry.date > from {
                last = max(last, entry.date)
                guard let source = Self.source(of: entry) else { continue }
                let key = "\(entry.date.timeIntervalSinceReferenceDate)|\(entry.composedMessage)"
                guard written[key] == nil else { continue }
                written[key] = entry.date
                let level = entry.level == .error || entry.level == .fault ? " ERROR" : ""
                text += "\(Self.time.string(from: entry.date)) [\(source)]\(level) \(entry.composedMessage)\n"
            }
            since = last
            written = written.filter { $0.value > last.addingTimeInterval(-Self.overlap * 2) }
            guard !text.isEmpty, let data = text.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: file) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: file)
            }
        }

        /// The label an entry is filed under, or nil for one not kept: all
        /// of Cue's, AVFoundation's errors, and the requests that failed in
        /// Cue — why a request of Cue's own never left (its error and the
        /// stream's code) is said only there.
        private static func source(of entry: OSLogEntryLog) -> String? {
            switch entry.subsystem {
            case "dance.cue":
                return entry.category
            case "com.apple.coremedia":
                return entry.composedMessage.contains("Error") ? "AVFoundation" : nil
            case "com.apple.CFNetwork":
                // A request's failure, with its error and the stream's own
                // code ("finished with error", "HTTP load failed"); not a
                // request Cue cancelled, nor the connection layer's chatter.
                let message = entry.composedMessage
                let failed = message.contains("finished with error") || message.contains("load failed")
                return failed && !message.contains("[-999]") ? "CFNetwork" : nil
            default:
                return nil
            }
        }

        private static let time: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()
    }
}
#endif
