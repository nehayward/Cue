import OSLog
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if DEBUG
/// Why a scroll stopped short, for Radio and Audiobooks (and Browse, to
/// compare): back from the background, a flick there stopped dead. Debug
/// builds only, always on, into the phone's own log (`PhoneLogFile`,
/// `Scripts/iphone-applog.sh`) under `dance.cue` `scroll`.
///
/// Each scroll of a list marked with `scrollStopLog(_:)` logs one line:
/// how far the finger took it, how fast it was flung and how far the fling
/// went against how far a fling that fast goes (UIKit's normal
/// deceleration), whether it ended at an edge, and everything noted since
/// the finger landed (1.5 s at least, 5 s at most):
///
///     radio: drag 0.21 s 180 pt, fling 2.6 pt/ms for 0.08 s, 35 of ~1297 pt — STOPPED EARLY;
///     before it: stall 240 ms, body radio ×6, defaults ×3
///
/// What's noted is what has caught a scroll in Cue before or could: the
/// main thread stalling (a watchdog pings it every 50 ms), UserDefaults
/// writes (any re-runs every `@AppStorage` view, the cause last time),
/// the tab screens' and `CueApp`'s bodies running, the tab bar accessory
/// re-hosted or changing placement, the list's insets or content height
/// changing under it, the list being made again, the set of tabs changing,
/// the network coming or going (`TabView`'s `.id`), and the app's own
/// foreground and background moves. A finger lifted while the list still
/// moved, with no fling after, is a pan that was dropped: "DROPPED".
///
/// The Search field losing its focus is logged the same way ("search field
/// lost focus; before it: …"), for the keyboard going down and up again
/// while someone types.
@MainActor
enum ScrollStopLog {
    private static let log = Logger(subsystem: "dance.cue", category: "scroll")

    /// What was noted lately, oldest first.
    private static var events: [(at: TimeInterval, what: String)] = []
    /// How far back a scroll's line looks.
    static let window: TimeInterval = 1.5

    /// Whether the watchdog pings the main thread: only while Cue is on
    /// screen. Written on the main thread, read on the watchdog's.
    nonisolated(unsafe) private static var isWatching = true

    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Starts the watchdog and the notes that come from outside a view.
    /// Once, at launch.
    static func start() {
        let center = NotificationCenter.default
        // Any write, of any key: the notification doesn't say which
        // (`DefaultsWriteLog` does, with `-dance.cue.logDefaultsWrites YES`).
        center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { note("defaults") }
        }
        #if canImport(UIKit)
        let moves: [(Notification.Name, String, Bool)] = [
            (UIApplication.willEnterForegroundNotification, "app entering foreground", true),
            (UIApplication.didBecomeActiveNotification, "app active", true),
            (UIApplication.willResignActiveNotification, "app resigning active", false),
            (UIApplication.didEnterBackgroundNotification, "app in background", false),
        ]
        for (name, what, watching) in moves {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    isWatching = watching
                    note(what, logNow: true)
                }
            }
        }
        #endif
        watchMainThread()
        log.notice("scroll stop log on: one line a scroll on Radio, Audiobooks and Browse, stalls over 100 ms")
    }

    /// Notes something that may catch a scroll. `logNow` logs it as well,
    /// for what's rare and telling on its own (a list made again, a stall).
    static func note(_ what: @autoclosure () -> String, logNow: Bool = false) {
        let what = what()
        let at = now
        events.append((at, what))
        // A scroll's line looks back 5 s at most.
        if events.count > 4000 {
            events.removeAll { $0.at < at - 6 }
        }
        if logNow {
            log.notice("\(what, privacy: .public)")
        }
    }

    /// The notes since `start`, each once with how many times it came, in
    /// the order they first came.
    static func summary(since start: TimeInterval) -> String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for event in events where event.at >= start {
            if counts[event.what] == nil { order.append(event.what) }
            counts[event.what, default: 0] += 1
        }
        guard !order.isEmpty else { return "nothing" }
        return order.map { what in
            let count = counts[what] ?? 1
            return count > 1 ? "\(what) ×\(count)" : what
        }.joined(separator: ", ")
    }

    static func report(_ line: String) {
        log.notice("\(line, privacy: .public)")
    }

    /// Logs `what` with everything noted in the last `window` seconds: the
    /// Search field losing its focus, say, and what came just before.
    static func reportRecent(_ what: String) {
        report("\(what); before it: \(summary(since: now - window))")
    }

    /// Pings the main thread every 50 ms from a thread of its own and
    /// notes each answer over 100 ms late: the main thread was busy that
    /// long, and a scroll on it can't move meanwhile.
    private static func watchMainThread() {
        Thread {
            let answered = DispatchSemaphore(value: 0)
            while true {
                guard isWatching else {
                    Thread.sleep(forTimeInterval: 0.5)
                    continue
                }
                Thread.sleep(forTimeInterval: 0.05)
                let sent = ProcessInfo.processInfo.systemUptime
                DispatchQueue.main.async {
                    let late = ProcessInfo.processInfo.systemUptime - sent
                    if late > 0.1 {
                        MainActor.assumeIsolated {
                            note("stall \(Int(late * 1000)) ms", logNow: true)
                        }
                    }
                    answered.signal()
                }
                answered.wait()
            }
        }.start()
    }
}

/// One scroll of a logged list, from the finger landing to rest.
private final class ScrollRun {
    var dragStart: (at: TimeInterval, y: CGFloat)?
    /// Where the fling began and how fast, in points a millisecond.
    var flingStart: (at: TimeInterval, y: CGFloat, speed: CGFloat?)?
    var animated = false
    /// The last few offsets, for how fast the list moved as the finger left.
    var recent: [(at: TimeInterval, y: CGFloat)] = []

    func reset() {
        dragStart = nil
        flingStart = nil
        animated = false
    }
}

/// Logs each scroll of the list it's on (`ScrollStopLog`).
private struct ScrollStopLogging: ViewModifier {
    let name: String

    /// A class, not values: written every frame of a scroll, and nothing
    /// on screen reads it.
    @State private var run = ScrollRun()

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { old, new, context in
                phaseChanged(from: old, to: new, context: context)
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                run.recent.append((ScrollStopLog.now, y))
                if run.recent.count > 8 { run.recent.removeFirst(run.recent.count - 8) }
            }
            .onScrollGeometryChange(for: EdgeInsets.self) { $0.contentInsets } action: { old, new in
                ScrollStopLog.note("\(name) insets top \(Int(old.top))→\(Int(new.top)) bottom \(Int(old.bottom))→\(Int(new.bottom))")
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, _ in
                ScrollStopLog.note("\(name) content height changed")
            }
            .onAppear { ScrollStopLog.note("\(name) list appeared", logNow: true) }
            .onDisappear { ScrollStopLog.note("\(name) list went", logNow: true) }
    }

    private func phaseChanged(from old: ScrollPhase, to new: ScrollPhase, context: ScrollPhaseChangeContext) {
        let now = ScrollStopLog.now
        let y = context.geometry.contentOffset.y
        switch new {
        case .tracking, .interacting:
            if run.flingStart != nil || run.animated {
                // A finger caught the list while it moved: that scroll is
                // over, and this is a new one.
                finish(context: context, caught: true)
            }
            if new == .interacting, run.dragStart == nil {
                run.dragStart = (now, y)
            }
        case .decelerating:
            run.flingStart = (now, y, context.velocity.map { Self.pointsPerMillisecond(abs($0.dy)) })
        case .animating:
            run.animated = true
            if run.dragStart == nil {
                // Nobody touched it: the list was scrolled from code.
                run.dragStart = (now, y)
                ScrollStopLog.note("\(name) scrolled by code", logNow: true)
            }
        case .idle:
            finish(context: context, caught: false)
        @unknown default:
            break
        }
    }

    /// Logs the scroll just ended and starts over.
    private func finish(context: ScrollPhaseChangeContext, caught: Bool) {
        defer { run.reset() }
        // A tap: the finger landed and left without moving the list.
        guard let drag = run.dragStart else { return }
        let now = ScrollStopLog.now
        let geometry = context.geometry
        let y = geometry.contentOffset.y
        let top = -geometry.contentInsets.top
        let bottom = max(top, geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom)
        let atEdge = y <= top + 4 || y >= bottom - 4

        var parts: [String] = []
        var verdict: String?
        let dragEnd = run.flingStart?.at ?? now
        let dragged = (run.flingStart?.y ?? y) - drag.y
        parts.append("drag \(Self.seconds(dragEnd - drag.at)) \(Int(abs(dragged))) pt")

        if let fling = run.flingStart {
            let went = abs(y - fling.y)
            let lasted = now - fling.at
            if let speed = fling.speed {
                // UIKit's normal rate keeps 0.998 of the speed each
                // millisecond: a fling at v points a millisecond goes about
                // 499 v before it rests.
                let expected = speed * 499
                parts.append("fling \(String(format: "%.1f", speed)) pt/ms for \(Self.seconds(lasted)), \(Int(went)) of ~\(Int(expected)) pt")
                if !caught, !atEdge, expected > 150, went < expected * 0.35 {
                    verdict = "STOPPED EARLY"
                }
            } else {
                parts.append("fling for \(Self.seconds(lasted)), \(Int(went)) pt")
                if !caught, !atEdge, lasted < 0.2 {
                    verdict = "STOPPED EARLY"
                }
            }
            if caught { verdict = "caught by a touch" }
        } else if !run.animated, !caught {
            // UIKit flings whenever the finger leaves a moving list; no
            // fling after one that was moving means the pan ended for it.
            let speed = Self.speedAtEnd(run.recent, now: now)
            if speed > 0.3, !atEdge {
                verdict = "DROPPED (moving \(String(format: "%.1f", speed)) pt/ms, no fling)"
            }
        }
        if run.animated { parts.append("animated") }
        if atEdge { parts.append("at an edge") }

        var line = "\(name): " + parts.joined(separator: ", ")
        if let verdict { line += " — \(verdict)" }
        // Since the finger landed, and never less than the window (the
        // app coming back just before a short flick) nor more than 5 s.
        let lookBack = min(max(ScrollStopLog.window, now - drag.at), 5)
        line += "; before it: " + ScrollStopLog.summary(since: now - lookBack)
        ScrollStopLog.report(line)
    }

    /// The scroll's velocity in points a millisecond. SwiftUI's is UIKit's,
    /// points a millisecond, but a value in the hundreds can only be
    /// points a second.
    private static func pointsPerMillisecond(_ value: CGFloat) -> CGFloat {
        value > 50 ? value / 1000 : value
    }

    /// How fast the list moved over its last few offsets, points a
    /// millisecond, or 0 if it had stopped by `now` (a finger that rested
    /// before it left).
    private static func speedAtEnd(_ recent: [(at: TimeInterval, y: CGFloat)], now: TimeInterval) -> CGFloat {
        guard let last = recent.last, now - last.at < 0.1,
              let first = recent.last(where: { last.at - $0.at >= 0.03 }),
              last.at - first.at < 0.2 else { return 0 }
        return abs(last.y - first.y) / CGFloat((last.at - first.at) * 1000)
    }

    private static func seconds(_ interval: TimeInterval) -> String {
        String(format: "%.2f s", interval)
    }
}

extension View {
    /// Logs each scroll of this list, and what happened as it ended
    /// (`ScrollStopLog`). Debug builds only.
    func scrollStopLog(_ name: String) -> some View {
        modifier(ScrollStopLogging(name: name))
    }
}
#else
/// `ScrollStopLog` is Debug's; these are its calls, doing nothing.
enum ScrollStopLog {
    @inline(__always)
    static func note(_ what: @autoclosure () -> String, logNow: Bool = false) {}

    @inline(__always)
    static func reportRecent(_ what: @autoclosure () -> String) {}
}

extension View {
    @inline(__always)
    func scrollStopLog(_ name: String) -> some View { self }
}
#endif
