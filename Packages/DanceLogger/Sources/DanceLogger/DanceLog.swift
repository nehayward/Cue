import Foundation
#if canImport(os)
import os
#endif

/// A logger. Make one per area of the app, named for it, and log what
/// happened in a sentence someone reading a bug report can follow:
///
///     private static let log = DanceLog("route")
///     Self.log.notice("route → \(group.name): carrying \(items.count) items")
///
/// Every line goes two places:
/// - the system log, under the app's bundle identifier as the subsystem and
///   the logger's name as the category: Xcode's console and Console.app;
/// - the log files on the device (`DanceLogStore`), which outlive a crash or
///   a relaunch and can be read back, shown or exported for a bug report.
///
/// Messages are interpolated like `os.Logger`'s, `privacy: .public`
/// included, so a call written for one reads the same here. Unlike
/// `os.Logger`, nothing is hidden by default: what reaches the file is what
/// a bug report needs. Credentials — tokens, passwords, API keys — are taken
/// out of every line first (`Redactor`), but don't log them on purpose.
///
/// Levels, and what each is for:
/// - `debug`: detail for chasing one bug. Only recorded in Debug builds, or
///   while Detailed Logging is on (`DanceLogStore.isDetailed`); otherwise the
///   message isn't even built.
/// - `info`: the normal flow, worth seeing in a report.
/// - `notice`: a decision or a change of state.
/// - `warning`: something went wrong and the app recovered.
/// - `error`: something the user will have noticed failed.
/// - `fault`: a bug: a state that should never happen.
public struct DanceLog: Sendable {
    /// The system-log subsystem when none is given: the app's bundle
    /// identifier, so Console.app filters on `subsystem:<bundle id>`.
    public static let defaultSubsystem = Bundle.main.bundleIdentifier ?? "DanceLogger"

    public let subsystem: String
    public let category: String

    #if canImport(os)
    private let logger: Logger
    #endif

    public init(_ category: String, subsystem: String = DanceLog.defaultSubsystem) {
        self.subsystem = subsystem
        self.category = category
        #if canImport(os)
        logger = Logger(subsystem: subsystem, category: category)
        #endif
    }

    public func debug(_ message: @autoclosure () -> Message) {
        record(.debug, message)
    }

    public func info(_ message: @autoclosure () -> Message) {
        record(.info, message)
    }

    public func notice(_ message: @autoclosure () -> Message) {
        record(.notice, message)
    }

    public func warning(_ message: @autoclosure () -> Message) {
        record(.warning, message)
    }

    public func error(_ message: @autoclosure () -> Message) {
        record(.error, message)
    }

    public func fault(_ message: @autoclosure () -> Message) {
        record(.fault, message)
    }

    private func record(_ level: Level, _ message: () -> Message) {
        let store = DanceLogStore.shared
        guard level > .debug || store.recordsDebug else { return }
        // Redacted before the system log as well as the file: a sysdiagnose
        // carries the system log off the device too.
        let text = Redactor.redact(message().text)
        #if canImport(os)
        logger.log(level: level.osLogType, "\(text, privacy: .public)")
        #endif
        store.append(level: level, category: category, message: text)
    }
}

public extension DanceLog {
    /// For lines that belong to no one area: launches, the app going to the
    /// background and coming back.
    static let app = DanceLog("app")
}

// MARK: - Level

public extension DanceLog {
    /// How much a line matters. See `DanceLog` for what each level is for.
    enum Level: Int, Comparable, CaseIterable, Sendable {
        case debug, info, notice, warning, error, fault

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// The word the file shows for the level. `DanceLogStore` pads it to
        /// five characters so the categories line up.
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
            guard let level = Level.allCases.first(where: { $0.label == label }) else { return nil }
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
}
