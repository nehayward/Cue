import SwiftUI

/// One line of text that scrolls when it doesn't fit: it rests at the start
/// for `pauseDuration`, scrolls one full length, and repeats.
///
/// The scroll moves two copies of the text with `offset`. It used a Metal
/// distortion shader (`marquee.metal`) instead, which makes SwiftUI render the
/// text into a texture and run the shader every frame: on the Mac each scroll
/// allocated a fixed ~95 MB of GPU memory for ~2 s (8 of 8 song changes to a
/// long title, 0 of 8 with the offset).
struct MarqueeText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        // Horizontal only: a title that fits on one line shows as plain text.
        ViewThatFits(in: .horizontal) {
            Text(text)
            MarqueeScroller(text: text, speed: 0.65, spacing: 20, pauseDuration: 1.5)
        }
    }
}

private struct MarqueePausedKey: PreferenceKey {
    static var defaultValue: Bool = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

private struct MarqueeScroller: View {
    let text: String
    var speed: CGFloat
    var spacing: CGFloat
    var pauseDuration: Double

    /// The marquee must stop ticking the moment the app stops being looked at.
    ///
    /// `TimelineView(.animation)` is a per-display-frame schedule, and this app
    /// is not suspended when it leaves the screen: `NowPlayingSessionService`
    /// holds a silent `.playback` session under the Lock Screen card, so the
    /// process keeps running on the `audio` background mode. A timeline left
    /// unpaused there re-evaluates this body and its preference at frame rate
    /// for a title nobody can see — the same shape as the reverted scrubber
    /// interpolation, which measured ~30% CPU (see
    /// `Docs/LockScreenNowPlaying.md`). This view is on the player screen *and*
    /// in `MiniPlayerView`, which is mounted nearly everywhere, so it is
    /// effectively always alive.
    ///
    /// `.inactive` as well as `.background`: Control Centre, the app switcher
    /// and the Lock Screen all land there, and none of them are worth a frame.
    @Environment(\.scenePhase) private var scenePhase

    @State private var textWidth: CGFloat = 0
    @State private var startTime: Date? = nil
    @State private var isPaused: Bool = true

    var body: some View {
        // The hidden copy takes the offered width and one line of height; the
        // scrolling copies are drawn over it and clipped to it.
        Text(text)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                // 60 a second at most: on a 120 Hz screen every other frame
                // re-ran this for half a point of movement. Paused while the
                // text rests (`startTime` is nil then), not just off screen.
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: scenePhase != .active || startTime == nil)) { context in
                    HStack(spacing: spacing) {
                        Text(text)
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
                        Text(text)
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: -offset(at: context.date))
                    // A preference rather than `@State` written every frame:
                    // `onPreferenceChange` only fires when the phase flips.
                    .preference(key: MarqueePausedKey.self, value: offset(at: context.date) == 0)
                }
            }
            .clipped()
            .onPreferenceChange(MarqueePausedKey.self) { isPaused = $0 }
            .mask(LinearGradient(stops: [.init(color: isPaused ? .black : .clear, location: 0.0),
                                         .init(color: .black, location: 0.04),
                                         .init(color: .black, location: 0.95),
                                         .init(color: .clear, location: 1.0)], startPoint: .leading, endPoint: .trailing))
            // Keyed on the phase as well as the text, so coming back on screen
            // restarts the cycle from rest.
            //
            // Elapsed time is measured from `startTime`, a wall clock, and
            // pausing the timeline doesn't pause that — it only stops us
            // reading it. Resume without this and the offset jumps from
            // wherever the last drawn frame left it to wherever the cycle has
            // since wandered to, which reads as a glitch on every unlock.
            //
            // Each cycle rests at the start with the timeline paused, then
            // scrolls one full length — after which the second copy sits
            // exactly where the first began, so going back to rest is seamless.
            .task(id: CycleKey(text: text, isActive: scenePhase == .active)) {
                startTime = nil
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(pauseDuration))
                    guard !Task.isCancelled else { return }
                    startTime = Date()
                    try? await Task.sleep(for: .seconds(scrollDuration))
                    guard !Task.isCancelled else { return }
                    startTime = nil
                }
            }
    }

    private struct CycleKey: Equatable {
        let text: String
        let isActive: Bool
    }

    private var pointsPerSecond: CGFloat { 50 * speed }

    /// How long one full length takes to scroll by.
    private var scrollDuration: Double {
        Double((textWidth + spacing) / pointsPerSecond)
    }

    /// How far the text has scrolled at `date`, or 0 while it rests at the start.
    private func offset(at date: Date) -> CGFloat {
        guard let startTime, textWidth > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(startTime)
        return elapsed < scrollDuration ? CGFloat(elapsed) * pointsPerSecond : 0
    }
}
