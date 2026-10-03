import Foundation
#if canImport(os)
import os
#endif

/// Cue's logger. Make one per area of the app, named for it, and log what
/// happened in a sentence someone reading a support email can follow:
///
///     private static let log = CueLog("route")
///     Self.log.notice("route → \(group.nameWithCount): carrying \(items.count) items")
///
/// Every line goes two places:
/// - the system log, under the `dance.cue` subsystem and the logger's
///   category: Xcode's console, Console.app, and `Scripts/iphone-logs.sh`;
/// - the log file on the device (`LogStore`), which outlives a crash or a
///   relaunch and is what Settings ▸ Report a Problem attaches to the email.
///
/// It lives in MusicSearchKit because that is the one framework every Cue
/// process links once (it is dynamic): the app, SonosKit and the watch all
/// see the same `LogStore.shared`, so there is a single writer per file.
///
/// Messages are interpolated like `os.Logger`'s, `privacy: .public` included,
/// so a call written for one reads the same here. Unlike `os.Logger`, nothing
/// is hidden by default: what reaches the file is what support needs to see.
/// Sign-in secrets — tokens, passwords, Subsonic's salt — are taken out of
/// every line first (`LogRedactor`), but don't log them on purpose.
///
/// Levels, and what each is for:
/// - `debug`: detail for chasing one bug. Only recorded in Debug builds, or
///   while Detailed Logging is on (`LogStore.isDetailed`); otherwise the
///   message isn't even built.
/// - `info`: the normal flow, worth seeing in a report.
/// - `notice`: a decision or state change: a route switch, a scan finished.
/// - `warning`: something went wrong and Cue recovered.
/// - `error`: something the user will have noticed failed.
/// - `fault`: a bug in Cue: a state that should never happen.
public struct CueLog: Sendable {
    /// The unified-log subsystem for every Cue line: filter Console.app or
    /// `log stream` with `subsystem:dance.cue`.
    public static let subsystem = "dance.cue"

    public let category: String

    #if canImport(os)
    private let logger: Logger
    #endif

    public init(_ category: String) {
        self.category = category
        #if canImport(os)
        logger = Logger(subsystem: Self.subsystem, category: category)
        #endif
    }

    public func debug(_ message: @autoclosure () -> LogMessage) {
        record(.debug, message)
    }

    public func info(_ message: @autoclosure () -> LogMessage) {
        record(.info, message)
    }

    public func notice(_ message: @autoclosure () -> LogMessage) {
        record(.notice, message)
    }

    public func warning(_ message: @autoclosure () -> LogMessage) {
        record(.warning, message)
    }

    public func error(_ message: @autoclosure () -> LogMessage) {
        record(.error, message)
    }

    public func fault(_ message: @autoclosure () -> LogMessage) {
        record(.fault, message)
    }

    private func record(_ level: LogLevel, _ message: () -> LogMessage) {
        let store = LogStore.shared
        guard level > .debug || store.recordsDebug else { return }
        // Redacted before the system log as well as the file: a sysdiagnose
        // carries the system log off the device too.
        let text = LogRedactor.redact(message().text)
        #if canImport(os)
        logger.log(level: level.osLogType, "\(text, privacy: .public)")
        #endif
        store.append(level: level, category: category, message: text)
    }
}

public extension CueLog {
    /// For lines that belong to no one area: launches, the app going to the
    /// background and coming back.
    static let app = CueLog("app")
}

/// How much a line matters. See `CueLog` for what each level is for.
public enum LogLevel: Int, Comparable, CaseIterable, Sendable {
    case debug, info, notice, warning, error, fault

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The word the file shows for the level. `LogStore` pads it to five
    /// characters so the categories line up.
    public var label: String {
        switch self {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .notice: "NOTE"
        case .warning: "WARN"
        case .error: "ERROR"
        case .fault: "FAULT"
        }
    }

    init?(label: String) {
        guard let level = LogLevel.allCases.first(where: { $0.label == label }) else { return nil }
        self = level
    }

    #if canImport(os)
    var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .notice: .default
        // The system log has no level between default and error.
        case .warning, .error: .error
        case .fault: .fault
        }
    }
    #endif
}
