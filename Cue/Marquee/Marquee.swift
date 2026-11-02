import SwiftUI

/// One line of text that scrolls when it doesn't fit: it rests at the start
/// for `pauseDuration`, scrolls one full length, and repeats.
///
/// The scroll moves two copies of the text along the line, placed there by
/// `MarqueeLine` rather than drawn through a shader. It used a Metal
/// distortion shader (`marquee.metal`) instead, which makes SwiftUI render the
/// text into a texture and run the shader every frame: on the Mac each scroll
/// allocated a fixed ~95 MB of GPU memory for ~2 s (8 of 8 song changes to a
/// long title, 0 of 8 with the copies moved instead).
///
/// A title that fits rests where the caller's `multilineTextAlignment` puts
/// it (centred in the player, leading in the mini player); one that doesn't
/// rests at the leading edge. The one line is laid out either way
/// (`MarqueeLine`), not swapped for plain text by a `ViewThatFits`, which
/// changes its choice without animating: as the player's column widened or
/// narrowed with the queue panel, the title jumped to where it would end up
/// while everything round it moved. Laid out, it moves with them.
struct MarqueeText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        MarqueeScroller(text: text, speed: 0.65, spacing: 20, pauseDuration: 1.5)
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
    @Environment(\.multilineTextAlignment) private var textAlignment

    @State private var textWidth: CGFloat = 0
    /// The width offered to the line.
    @State private var lineWidth: CGFloat = 0
    @State private var startTime: Date? = nil
    @State private var isPaused: Bool = true

    /// The text fits the line, so it rests and never scrolls. Before it's
    /// measured it's taken to fit.
    private var fits: Bool {
        textWidth <= lineWidth + 0.5
    }

    /// Where a text that fits rests along the line: 0 leading, 1 trailing.
    private var restingPlace: CGFloat {
        switch textAlignment {
        case .leading: 0
        case .center: 0.5
        case .trailing: 1
        }
    }

    var body: some View {
        // The hidden copy takes the offered width and one line of height; the
        // scrolling copies are drawn over it and clipped to it.
        Text(text)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { lineWidth = $0 }
            .overlay {
                // The timeline only while the text scrolls; resting, the line
                // is a plain view. A timeline paused in its place kept the
                // frame it last drew: a scroll called off part-way, the line
                // having grown to fit the text (the queue panel closing),
                // stayed where it stopped, both copies showing and off the
                // line's middle.
                if let startTime {
                    // 60 a second at most: on a 120 Hz screen every other
                    // frame re-ran this for half a point of movement. Paused
                    // off screen.
                    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: scenePhase != .active)) { context in
                        let scrolled = offset(since: startTime, at: context.date)
                        line(scrolled: scrolled)
                            // A preference rather than `@State` written every
                            // frame: `onPreferenceChange` only fires when the
                            // phase flips.
                            .preference(key: MarqueePausedKey.self, value: scrolled == 0)
                    }
                } else {
                    line(scrolled: 0)
                        .preference(key: MarqueePausedKey.self, value: true)
                }
            }
            .clipped()
            .onPreferenceChange(MarqueePausedKey.self) { isPaused = $0 }
            .mask(LinearGradient(stops: [.init(color: isPaused ? .black : .clear, location: 0.0),
                                         .init(color: .black, location: 0.04),
                                         .init(color: .black, location: 0.95),
                                         .init(color: fits ? .black : .clear, location: 1.0)], startPoint: .leading, endPoint: .trailing))
            // Caught mid-scroll by a line that's grown to fit it (the queue
            // panel closing), it fades back to rest rather than jumping.
            .onChange(of: fits) { _, fits in
                guard fits, startTime != nil else { return }
                withAnimation(.snappy) {
                    startTime = nil
                }
            }
            // Keyed on the phase as well as the text, so coming back on screen
            // restarts the cycle from rest.
            //
            // Elapsed time is measured from `startTime`, a wall clock, and
            // pausing the timeline doesn't pause that — it only stops us
            // reading it. Resume without this and the offset jumps from
            // wherever the last drawn frame left it to wherever the cycle has
            // since wandered to, which reads as a glitch on every unlock.
            //
            // Each cycle rests at the start with no timeline, then
            // scrolls one full length — after which the second copy sits
            // exactly where the first began, so going back to rest is seamless.
            .task(id: CycleKey(text: text, isActive: scenePhase == .active, fits: fits)) {
                startTime = nil
                guard !fits else { return }
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

    /// The text twice, laid out by `MarqueeLine`.
    private func line(scrolled: CGFloat) -> some View {
        MarqueeLine(restingPlace: restingPlace, spacing: spacing, scrolled: scrolled) {
            Text(text)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            Text(text)
                .accessibilityHidden(true)
        }
        .lineLimit(1)
    }

    private struct CycleKey: Equatable {
        let text: String
        let isActive: Bool
        let fits: Bool
    }

    private var pointsPerSecond: CGFloat { 50 * speed }

    /// How long one full length takes to scroll by.
    private var scrollDuration: Double {
        Double((textWidth + spacing) / pointsPerSecond)
    }

    /// How far the text has scrolled at `date` in a scroll begun at
    /// `startTime`, or 0 once it has gone the full length.
    private func offset(since startTime: Date, at date: Date) -> CGFloat {
        guard textWidth > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(startTime)
        return elapsed < scrollDuration ? CGFloat(elapsed) * pointsPerSecond : 0
    }
}

/// The marquee's one line: the text and its copy. Longer than the line, the
/// text starts at the leading edge, `scrolled` points along, with the copy
/// after it; one that fits rests where `restingPlace` puts it (0 leading,
/// 0.5 centred, 1 trailing), whatever `scrolled` says, its copy out past the
/// line's end where the clip hides it. The layout decides from the widths
/// it's laying out, not from measured state, so nothing a frame late can
/// draw a text that fits off its place, and a change of the line's width
/// moves the text in the same animation as the views round it.
private struct MarqueeLine: Layout {
    var restingPlace: CGFloat
    var spacing: CGFloat
    var scrolled: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let textWidth = subviews[0].sizeThatFits(.unspecified).width
        let fits = textWidth <= bounds.width
        let x = fits ? (bounds.width - textWidth) * restingPlace : -scrolled
        let copyX = fits ? bounds.width + spacing : x + textWidth + spacing
        subviews[0].place(at: CGPoint(x: bounds.minX + x, y: bounds.midY), anchor: .leading, proposal: .unspecified)
        subviews[1].place(at: CGPoint(x: bounds.minX + copyX, y: bounds.midY), anchor: .leading, proposal: .unspecified)
    }
}
