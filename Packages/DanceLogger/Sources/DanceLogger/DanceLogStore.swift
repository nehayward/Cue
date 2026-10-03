import Foundation

/// The log files on the device: every `DanceLog` line, kept for a week,
/// plain text a person can read, ready to read back, show or attach to a
/// bug report (`exportFile(header:title:limit:)`).
///
/// The system log is the better tool at a desk, but on someone else's phone
/// it's out of reach, it forgets a process once it exits, and it drops most
/// of what isn't an error. So `DanceLog` writes here as well.
///
/// The files are `Library/Logs/DanceLogger/log-<start time>.log` in the
/// app's container, one or more a day: a new one starts when the day changes
/// or the current one passes `maxFileSize`, and a launch carries on today's
/// last file while it has room. Files older than `retention` go, and the
/// oldest go while the folder is over `maxTotalSize`. A line looks like
///
///     2026-10-03 14:22:05.123 ERROR [route] route → Kitchen: replace failed: …
///
/// with the time in the device's own time zone, and each launch can open
/// with a banner naming the app version and the device (`beginSession(_:)`).
///
/// Lines are written in order on a background queue, straight to the file
/// with no buffer of their own, so what was logged before a crash is there
/// after it.
public final class DanceLogStore: @unchecked Sendable {
    public static let shared = DanceLogStore()

    public let directory: URL
    let maxFileSize: Int
    let maxTotalSize: Int
    let retention: TimeInterval
    /// Longer messages — a server's whole response, say — are cut here.
    let maxMessageLength = 8_000
    private let defaults: UserDefaults

    private let queue = DispatchQueue(label: "DanceLogger.store", qos: .utility)

    // Only touched on `queue`.
    private var handle: FileHandle?
    private var handleDay: String?
    private var handleSize = 0
    private let lineFormatter = DanceLogStore.formatter("yyyy-MM-dd HH:mm:ss.SSS")
    private let dayFormatter = DanceLogStore.formatter("yyyy-MM-dd")
    private let fileFormatter = DanceLogStore.formatter("yyyy-MM-dd-HHmmss-SSS")

    init(
        directory: URL? = nil,
        maxFileSize: Int = DanceLogStore.defaultMaxFileSize,
        maxTotalSize: Int = DanceLogStore.defaultMaxTotalSize,
        retention: TimeInterval = 7 * 24 * 60 * 60,
        defaults: UserDefaults = .standard
    ) {
        self.directory = directory ?? Self.defaultDirectory
        self.maxFileSize = maxFileSize
        self.maxTotalSize = maxTotalSize
        self.retention = retention
        self.defaults = defaults
    }

    deinit {
        try? handle?.close()
    }

    // A watch has little room, so it keeps far less.
    #if os(watchOS)
    static let defaultMaxFileSize = 256 * 1024
    static let defaultMaxTotalSize = 1024 * 1024
    #else
    static let defaultMaxFileSize = 2 * 1024 * 1024
    static let defaultMaxTotalSize = 20 * 1024 * 1024
    #endif

    /// `Library/Logs/DanceLogger`. On the Mac that is where Console.app looks
    /// for an app's logs; it is kept out of backups (`prepareDirectory`).
    private static var defaultDirectory: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("DanceLogger", isDirectory: true)
    }

    /// Every log file's name starts with this, then the time it started.
    static let filePrefix = "log-"

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }

    // MARK: - Detailed Logging

    /// Until when Detailed Logging is on, as seconds since the reference
    /// date. A time rather than a switch, so it can't be left on for good.
    public static let detailedUntilKey = "DanceLogger.detailedUntil"

    /// How long Detailed Logging stays on once switched on.
    public static let detailedDuration: TimeInterval = 24 * 60 * 60

    /// Detailed Logging: `debug` lines are recorded as well. For asking
    /// someone to reproduce a problem with everything written down; it
    /// turns itself off after `detailedDuration`.
    public var isDetailed: Bool {
        get { detailedUntil.map { $0 > .now } ?? false }
        set { detailedUntil = newValue ? .now.addingTimeInterval(Self.detailedDuration) : nil }
    }

    /// When Detailed Logging turns itself off, while it's on.
    public var detailedUntil: Date? {
        get {
            let seconds = defaults.double(forKey: Self.detailedUntilKey)
            return seconds > 0 ? Date(timeIntervalSinceReferenceDate: seconds) : nil
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSinceReferenceDate, forKey: Self.detailedUntilKey)
            } else {
                defaults.removeObject(forKey: Self.detailedUntilKey)
            }
        }
    }

    /// Whether `debug` lines are recorded: always in a Debug build, and
    /// while Detailed Logging is on.
    public var recordsDebug: Bool {
        #if DEBUG
        return true
        #else
        return isDetailed
        #endif
    }

    // MARK: - Writing

    /// Opens a launch in the file with a banner, so a reader can see where
    /// one run of the app ends and the next begins, and on what.
    public func beginSession(_ summary: String) {
        let date = Date.now
        queue.async {
            let stamp = self.lineFormatter.string(from: date)
            self.write("\n──── \(stamp) · Launched · \(summary) ────\n", at: date)
        }
    }

    func append(level: DanceLog.Level, category: String, message: String, at date: Date = .now) {
        queue.async {
            self.write(self.line(level: level, category: category, message: message, at: date), at: date)
        }
    }

    private func line(level: DanceLog.Level, category: String, message: String, at date: Date) -> String {
        var message = message
        if message.count > maxMessageLength {
            let cut = message.count - maxMessageLength
            message = String(message.prefix(maxMessageLength)) + " … (\(cut) more characters)"
        }
        // A message over several lines stays one entry: its later lines are
        // indented under the first.
        if message.contains("\n") {
            message = message
                .split(separator: "\n", omittingEmptySubsequences: false)
                .joined(separator: "\n    ")
        }
        let level = level.label.padding(toLength: 5, withPad: " ", startingAt: 0)
        return "\(lineFormatter.string(from: date)) \(level) [\(category)] \(message)\n"
    }

    private func write(_ text: String, at date: Date) {
        let data = Data(text.utf8)
        let day = dayFormatter.string(from: date)
        if handle == nil || day != handleDay || handleSize + data.count > maxFileSize {
            open(day: day, at: date)
        }
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
            handleSize += data.count
        } catch {
            // The disk is full, or the file went: start afresh with the next line.
            closeHandle()
        }
    }

    /// Opens the file the next line goes in: today's last one if this is the
    /// first line of the launch and it has room, a new one otherwise.
    private func open(day: String, at date: Date) {
        let isFirstOfLaunch = handle == nil && handleDay == nil
        closeHandle()
        prepareDirectory()

        var url: URL?
        var size = 0
        if isFirstOfLaunch, let last = logFiles().last, last.lastPathComponent.hasPrefix("\(Self.filePrefix)\(day)-") {
            let lastSize = Self.size(of: last)
            if lastSize < maxFileSize {
                url = last
                size = lastSize
            }
        }
        if url == nil {
            url = newFile(startingAt: date)
        }

        guard let url, let handle = try? FileHandle(forWritingTo: url) else { return }
        _ = try? handle.seekToEnd()
        self.handle = handle
        handleDay = day
        handleSize = size
        prune(keeping: url)
    }

    /// A new, empty file named for `date`. The names are what orders the
    /// files, so it must sort after the newest one: one started in the same
    /// millisecond (or after a name was freed by `prune`) moves on a
    /// millisecond at a time until it does.
    private func newFile(startingAt date: Date) -> URL? {
        let newest = logFiles().last?.lastPathComponent ?? ""
        var stamp = date
        var url = directory.appendingPathComponent("\(Self.filePrefix)\(fileFormatter.string(from: stamp)).log")
        var attempts = 0
        while url.lastPathComponent <= newest, attempts < 1_000 {
            stamp.addTimeInterval(0.001)
            url = directory.appendingPathComponent("\(Self.filePrefix)\(fileFormatter.string(from: stamp)).log")
            attempts += 1
        }
        // Only if the clock went back further than that: never write over a file.
        guard !FileManager.default.fileExists(atPath: url.path) else { return nil }
        return FileManager.default.createFile(atPath: url.path, contents: nil) ? url : nil
    }

    private func closeHandle() {
        try? handle?.close()
        handle = nil
    }

    private func prepareDirectory() {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if canImport(Darwin)
        var directory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        #endif
    }

    /// Removes files past `retention`, then the oldest while the folder is
    /// over `maxTotalSize`. Never the one being written.
    private func prune(keeping current: URL) {
        let cutoff = Date.now.addingTimeInterval(-retention)
        var files = logFiles().filter { $0 != current }
        for file in files where Self.modificationDate(of: file) < cutoff {
            try? FileManager.default.removeItem(at: file)
        }
        files = logFiles().filter { $0 != current }
        var total = logFiles().reduce(0) { $0 + Self.size(of: $1) }
        while total > maxTotalSize, let oldest = files.first {
            total -= Self.size(of: oldest)
            try? FileManager.default.removeItem(at: oldest)
            files.removeFirst()
        }
    }

    // MARK: - Reading

    /// The log files, oldest first. Their names sort by when they started.
    public func logFiles() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { $0.hasPrefix(Self.filePrefix) && $0.hasSuffix(".log") }
            .sorted()
            .map { directory.appendingPathComponent($0) }
    }

    /// Waits until every line logged so far is in the file.
    public func flush() {
        queue.sync {}
    }

    /// The most recent `limit` bytes of the log, oldest line first, cut at
    /// the start of a line. Blocks until what's been logged so far is
    /// written, so don't call it on the main thread.
    public func recentText(limit: Int = 4 * 1024 * 1024) -> String {
        queue.sync {
            var chunks: [Data] = []
            var remaining = limit
            var trimmed = false
            for file in logFiles().reversed() {
                guard remaining > 0 else {
                    trimmed = true
                    break
                }
                guard var data = try? Data(contentsOf: file) else { continue }
                if data.count > remaining {
                    data = data.suffix(remaining)
                    // Start at the first whole line.
                    if let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
                        data = data.suffix(from: data.index(after: newline))
                    }
                    trimmed = true
                }
                remaining -= data.count
                chunks.insert(data, at: 0)
            }
            let text = chunks.map { String(decoding: $0, as: UTF8.self) }.joined()
            return trimmed ? "… (earlier lines left out)\n" + text : text
        }
    }

    /// Writes `header`, a blank line and the recent log to a text file named
    /// `<title> Log <now>.txt`, ready to attach or share, and returns where it
    /// is. The file sits in the temporary folder and replaces the one made
    /// before it.
    public func exportFile(header: String, title: String = DanceLogStore.appName, limit: Int = 4 * 1024 * 1024) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Log Export", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(title) Log \(Self.formatter("yyyy-MM-dd HHmm").string(from: .now)).txt"
        let url = folder.appendingPathComponent(name)
        let text = header + "\n\n" + recentText(limit: limit)
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    /// The app's name as the Home Screen shows it, for the exported file's.
    public static var appName: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String ?? "App"
    }

    /// Deletes every log file. The next line starts a new one.
    public func clear() {
        queue.sync {
            closeHandle()
            handleDay = nil
            for file in logFiles() {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// How much room the log files take.
    public func totalSize() -> Int {
        queue.sync {
            logFiles().reduce(0) { $0 + Self.size(of: $1) }
        }
    }

    private static func size(of url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

    private static func modificationDate(of url: URL) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date ?? .distantPast
    }
}

// MARK: - Entries

public extension DanceLogStore {
    /// One line of the log, read back to show it.
    struct Entry: Identifiable, Sendable {
        public let id: Int
        /// `yyyy-MM-dd HH:mm:ss.SSS`, as written.
        public let timestamp: String
        /// Nil for a launch banner or a line the store didn't write itself.
        public let level: DanceLog.Level?
        public let category: String
        public let message: String

        public var isLaunch: Bool { level == nil && message.hasPrefix("──── ") }
    }

    private static let entryPattern = try! NSRegularExpression(
        pattern: #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}) ([A-Z]+) *\[([^\]]*)\] (.*)$"#
    )

    /// Splits log text into entries, oldest first. A message's later lines
    /// (indented in the file) stay with it.
    static func entries(in text: String) -> [Entry] {
        var entries: [Entry] = []
        var pending: (timestamp: String, level: DanceLog.Level?, category: String, lines: [Substring])?

        func finish() {
            guard let entry = pending else { return }
            entries.append(Entry(
                id: entries.count,
                timestamp: entry.timestamp,
                level: entry.level,
                category: entry.category,
                message: entry.lines.joined(separator: "\n")
            ))
            pending = nil
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("    "), pending != nil {
                pending?.lines.append(line.dropFirst(4))
                continue
            }
            finish()
            let string = String(line)
            let range = NSRange(string.startIndex..., in: string)
            if let match = entryPattern.firstMatch(in: string, range: range),
               let timestamp = Range(match.range(at: 1), in: string),
               let label = Range(match.range(at: 2), in: string),
               let category = Range(match.range(at: 3), in: string),
               let message = Range(match.range(at: 4), in: string) {
                pending = (
                    String(string[timestamp]),
                    DanceLog.Level(label: String(string[label])),
                    String(string[category]),
                    [string[message]]
                )
            } else {
                pending = ("", nil, "", [line])
            }
        }
        finish()
        return entries
    }
}
