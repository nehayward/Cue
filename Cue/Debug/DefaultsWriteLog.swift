#if DEBUG
import Foundation
import ObjectiveC
import OSLog

/// Logs every UserDefaults write, for finding what writes too often. Any
/// write re-runs every view holding `@AppStorage` (`CueApp` and each tab's
/// screen among them), so a key written a few times a second redraws the
/// app nonstop: Search re-saving its selected services ~35 times a second
/// kept Radio's list from scrolling, and nothing else pointed at it.
/// Debug builds only.
///
/// Launched with `-dance.cue.logDefaultsWrites YES`, it counts the writes
/// by key, from any thread, and every 2 s logs which keys were written how
/// often, under `dance.cue` `defaults` (so in the phone's own log,
/// `Scripts/iphone-applog.sh`). The first write of each key logs the app's
/// frames that made it, mangled: `xcrun swift-demangle` reads them.
enum DefaultsWriteLog {
    private static let log = Logger(subsystem: "dance.cue", category: "defaults")
    private static let lock = NSLock()
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    nonisolated(unsafe) private static var seen: Set<String> = []

    static func startIfRequested() {
        guard UserDefaults.standard.bool(forKey: "dance.cue.logDefaultsWrites") else { return }
        swapSetters()
        Thread {
            while true {
                Thread.sleep(forTimeInterval: 2)
                lock.lock()
                let written = counts
                counts = [:]
                lock.unlock()
                guard !written.isEmpty else { continue }
                let line = written.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
                log.notice("writes in 2 s: \(line, privacy: .public)")
            }
        }.start()
    }

    /// Each setter's own implementation, with a count in front.
    private static func swapSetters() {
        let defaults: AnyClass = UserDefaults.self
        func method(_ name: String) -> (Method, Selector)? {
            let selector = NSSelectorFromString(name)
            return class_getInstanceMethod(defaults, selector).map { ($0, selector) }
        }
        if let (method, selector) = method("setObject:forKey:") {
            typealias Original = @convention(c) (AnyObject, Selector, AnyObject?, NSString) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
            let block: @convention(block) (AnyObject, AnyObject?, NSString) -> Void = { store, value, key in
                note(key as String)
                original(store, selector, value, key)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
        if let (method, selector) = method("setBool:forKey:") {
            typealias Original = @convention(c) (AnyObject, Selector, Bool, NSString) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
            let block: @convention(block) (AnyObject, Bool, NSString) -> Void = { store, value, key in
                note(key as String)
                original(store, selector, value, key)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
        if let (method, selector) = method("setInteger:forKey:") {
            typealias Original = @convention(c) (AnyObject, Selector, Int, NSString) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
            let block: @convention(block) (AnyObject, Int, NSString) -> Void = { store, value, key in
                note(key as String)
                original(store, selector, value, key)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
        if let (method, selector) = method("setDouble:forKey:") {
            typealias Original = @convention(c) (AnyObject, Selector, Double, NSString) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
            let block: @convention(block) (AnyObject, Double, NSString) -> Void = { store, value, key in
                note(key as String)
                original(store, selector, value, key)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
        if let (method, selector) = method("removeObjectForKey:") {
            typealias Original = @convention(c) (AnyObject, Selector, NSString) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
            let block: @convention(block) (AnyObject, NSString) -> Void = { store, key in
                note("remove \(key)")
                original(store, selector, key)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
    }

    private static func note(_ key: String) {
        lock.lock()
        counts[key, default: 0] += 1
        let isFirst = seen.insert(key).inserted
        lock.unlock()
        guard isFirst else { return }
        // The app's own frames, nearest first: who wrote it.
        let frames = Thread.callStackSymbols.dropFirst(2)
            .filter { $0.contains("Cue.debug.dylib") || $0.contains("Kit ") || $0.contains("Defaults ") }
            .filter { !$0.contains("DefaultsWriteLog") }
            .prefix(6)
            .compactMap { $0.split(separator: " ").dropFirst(3).first.map(String.init) }
        log.notice("first write of \(key, privacy: .public) on \(Thread.isMainThread ? "main" : "a background thread", privacy: .public) from \(frames.joined(separator: " < "), privacy: .public)")
    }
}
#endif
