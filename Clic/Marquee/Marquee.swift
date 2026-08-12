import SwiftUI

struct MarqueeText: View {
    let text: String
    @State private var isPaused: Bool = false
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        ViewThatFits {
            Text(text)
            ScrollView(.horizontal) {
                Text(text)
                    .lineLimit(1)
                    .fixedSize()
                    .marquee(speed: 0.65, spacing: 20, pauseDuration: 1.5, id: text)
            }
            .scrollDisabled(true)
            .onPreferenceChange(MarqueePausedKey.self) { isPaused in
                self.isPaused = isPaused
            }
            .mask(LinearGradient(stops: [.init(color: isPaused ? .black : .clear, location: 0.0),
                                         .init(color: .black, location: 0.04),
                                         .init(color: .black, location: 0.95),
                                         .init(color: .clear, location: 1.0)], startPoint: .leading, endPoint: .trailing))
        }
    }
}

extension View {
    @ViewBuilder
    func marquee(speed: CGFloat = 1, spacing: CGFloat = 80, pauseDuration: Double = 2.0, id: String) -> some View {
        modifier(
            MarqueeViewModifier(
                speed: speed,
                spacing: spacing,
                pauseDuration: pauseDuration,
                id: id
            )
        )
    }
}

struct MarqueePausedKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

fileprivate struct MarqueeViewModifier: ViewModifier {
    var speed: CGFloat
    var spacing: CGFloat
    var pauseDuration: Double
    let id: String

    /// The marquee must stop ticking the moment the app stops being looked at.
    ///
    /// `TimelineView(.animation)` is a per-display-frame schedule, and this app
    /// is not suspended when it leaves the screen: `NowPlayingSessionService`
    /// holds a silent `.playback` session under the Lock Screen card, so the
    /// process keeps running on the `audio` background mode. A timeline left
    /// unpaused there re-evaluates this body, its shader input and its
    /// preference at frame rate for a title nobody can see — the same shape as
    /// the reverted scrubber interpolation, which measured ~30% CPU (see
    /// `Docs/LockScreenNowPlaying.md`). This view is on the player screen *and*
    /// in `MiniPlayerView`, which is mounted nearly everywhere, so it is
    /// effectively always alive.
    ///
    /// `.inactive` as well as `.background`: Control Centre, the app switcher
    /// and the Lock Screen all land there, and none of them are worth a frame.
    @Environment(\.scenePhase) private var scenePhase

    @State var size: CGSize = .zero
    @State private var startTime: Date? = nil

    init(speed: CGFloat, spacing: CGFloat, pauseDuration: Double, id: String) {
        self.speed = speed
        self.spacing = spacing
        self.pauseDuration = pauseDuration
        self.id = id
    }

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: scenePhase != .active)) { context in
            effect(content: content, date: context.date)
                // Derived, not mirrored into `@State` from an `.onChange` on
                // `context.date`: that wrote a value every frame, and a `@State`
                // write invalidates this modifier — which invalidates the
                // `ViewThatFits` above it, so both candidate layouts were
                // measured again on every frame. As a preference it costs a
                // value comparison, and `onPreferenceChange` still only fires
                // when the phase actually flips.
                .preference(key: MarqueePausedKey.self, value: isPaused(at: context.date))
        }
        // Keyed on the phase as well as the text, so coming back on screen
        // restarts the cycle from rest.
        //
        // Elapsed time is measured from `startTime`, a wall clock, and pausing
        // the timeline doesn't pause that — it only stops us reading it. Resume
        // without this and the offset jumps from wherever the last drawn frame
        // left it to wherever the cycle has since wandered to, which reads as a
        // glitch on every unlock. Restarting is also just the better look: a
        // title that begins again is how you'd want to find it.
        .task(id: CycleKey(text: id, isActive: scenePhase == .active)) {
            startTime = nil
            try? await Task.sleep(for: .seconds(pauseDuration))
            startTime = Date()
        }
    }

    private struct CycleKey: Equatable {
        let text: String
        let isActive: Bool
    }

    /// Shader input for `date`: how far into the scrolling half of the cycle we
    /// are, or 0 while the marquee is resting at the start.
    private func effectiveTime(at date: Date) -> Double {
        // Only start measuring elapsed time once animation begins
        let elapsedTime = startTime.map { date.timeIntervalSince($0) } ?? 0
        let animationCycleDuration = (size.width + spacing) / (50 * speed)

        // Calculate animation phase
        let totalCycleDuration = animationCycleDuration + pauseDuration
        let cycleProgress = elapsedTime.truncatingRemainder(dividingBy: totalCycleDuration)
        let shouldAnimate = cycleProgress < animationCycleDuration

        // Calculate effective time for shader, starting from 0 when animation begins
        return shouldAnimate ? cycleProgress * speed : 0
    }

    private func isPaused(at date: Date) -> Bool {
        effectiveTime(at: date) == 0
    }

    @ViewBuilder
    func effect(content: Content, date: Date) -> some View {
        let effectiveTime = effectiveTime(at: date)

        content
            .onGeometryChange(for: CGSize.self) { proxy in
                return proxy.size
            } action: { newValue in
                size = newValue
            }
            .distortionEffect(
                ShaderLibrary.marquee(
                    .float(effectiveTime
                          ),
                    .float(size.width + spacing)
                ),
                maxSampleOffset: .zero
            )
    }
}
