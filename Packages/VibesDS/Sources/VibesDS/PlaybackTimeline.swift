import SwiftUI

/// Redraws `content` with a running playback position — and only while that's
/// worth doing.
///
/// Progress bars draw from an estimate that runs forward from the last
/// reported position (`Room.estimatedPlaybackPosition()` in SonosKit) rather
/// than the stored number, so something has to redraw them as time passes.
/// That something must stop whenever nobody can see the result: Clic holds a
/// silent audio session for the Lock Screen card, so the process stays alive —
/// and a locked phone with Clic frontmost doesn't reliably reach
/// `.background` — and an unconditional timeline kept ticking behind the Lock
/// Screen. So it ticks only while all of these hold:
///
/// - the scene is active (not locked, not in the app switcher),
/// - the view is on screen (not under a pushed screen or a covering sheet),
/// - `isRunning`: playback is actually moving, and nothing (a finger on the
///   scrubber) is holding it still.
///
/// Otherwise it's paused and costs nothing; `content` still redraws whenever
/// what `position` reads changes.
///
/// A `TimelineView` rather than a `CADisplayLink`: the `.animation` schedule is
/// driven by the display link already, throttled to `minimumInterval` and
/// paused by SwiftUI itself, without a UIKit bridge or a lifecycle to manage.
public struct PlaybackTimeline<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOnScreen = false

    private let isRunning: Bool
    private let minimumInterval: TimeInterval
    private let position: () -> TimeInterval
    private let content: (_ position: TimeInterval) -> Content

    /// - Parameters:
    ///   - isRunning: Whether the position is moving on its own right now.
    ///   - minimumInterval: How often the content needs to change. Anything
    ///     shorter than a pixel of progress is wasted work.
    ///   - position: The position to draw, read on every tick.
    public init(
        isRunning: Bool,
        minimumInterval: TimeInterval,
        position: @escaping () -> TimeInterval,
        @ViewBuilder content: @escaping (_ position: TimeInterval) -> Content
    ) {
        self.isRunning = isRunning
        self.minimumInterval = minimumInterval
        self.position = position
        self.content = content
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: minimumInterval, paused: isPaused)) { _ in
            content(position())
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
    }

    private var isPaused: Bool {
        !isRunning || !isOnScreen || scenePhase != .active
    }
}

/// How often a progress display is worth redrawing.
public enum ProgressRedraw {
    /// How often a progress bar needs redrawing: once per pixel of progress,
    /// and at least once a second for a time label drawn alongside it. A
    /// three-minute song across a phone-width bar moves a pixel roughly every
    /// 0.17 s; an hour-long episode, every few seconds. Anything faster
    /// redraws the same frame.
    ///
    /// - Parameters:
    ///   - duration: The track's length, in milliseconds. Zero (a live
    ///     stream) has no bar to move.
    ///   - length: The bar's length, in points.
    ///   - scale: The display scale, for pixels per point.
    public static func interval(forDuration duration: TimeInterval, length: CGFloat, scale: CGFloat) -> TimeInterval {
        let pixels = length * scale
        guard duration > 0, pixels > 0 else { return 1 }
        return min(max(duration / 1000 / pixels, 1.0 / 30), 1)
    }
}
