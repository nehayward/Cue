import SwiftUI

/// A single line of text that scrolls when it doesn't fit, resting at the start
/// between passes.
///
/// Driven by a `.task` loop that animates an `.offset`, not by a per-frame
/// `TimelineView`. SwiftUI interpolates the offset on its own, so `body` is
/// evaluated about twice per cycle instead of on every display frame, and the
/// rest between passes renders nothing at all. The text is laid out twice side
/// by side: scrolling exactly one copy's width plus `spacing` puts the second
/// copy where the first started, so snapping back to 0 is invisible.
struct MarqueeText: View {
    let text: String
    /// Points per second.
    var speed: CGFloat = 32.5
    var spacing: CGFloat = 20
    var pause: Duration = .seconds(1.5)

    /// The marquee must stop the moment the app stops being looked at.
    ///
    /// This app is not suspended when it leaves the screen:
    /// `NowPlayingSessionService` holds a silent `.playback` session under the
    /// Lock Screen card, so the process keeps running on the `audio` background
    /// mode, and a loop left running there animates a title nobody can see (see
    /// `Docs/LockScreenNowPlaying.md`). This view is on the player screen *and*
    /// in `MiniPlayerView`, which is mounted nearly everywhere, so it is
    /// effectively always alive.
    ///
    /// `.inactive` as well as `.background`: Control Centre, the app switcher
    /// and the Lock Screen all land there, and none of them are worth a frame.
    @Environment(\.scenePhase) private var scenePhase

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isScrolling = false

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text)
                .lineLimit(1)
            HStack(spacing: spacing) {
                Text(text)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { width in
                        textWidth = width
                    }
                Text(text)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            .lineLimit(1)
            .offset(x: offset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: isScrolling ? .clear : .black, location: 0.0),
                                         .init(color: .black, location: 0.04),
                                         .init(color: .black, location: 0.95),
                                         .init(color: .clear, location: 1.0)], startPoint: .leading, endPoint: .trailing))
            // Keyed on the phase as well as the text, so leaving the screen
            // cancels the loop and coming back restarts the cycle from rest.
            .task(id: CycleKey(text: text, width: textWidth, isActive: scenePhase == .active)) {
                await scroll()
            }
        }
    }

    private struct CycleKey: Equatable {
        let text: String
        let width: CGFloat
        let isActive: Bool
    }

    private func scroll() async {
        reset()
        guard scenePhase == .active, textWidth > 0 else { return }

        let distance = textWidth + spacing
        let duration = Double(distance / speed)

        while !Task.isCancelled {
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }

            isScrolling = true
            withAnimation(.linear(duration: duration)) {
                offset = -distance
            }

            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }

            reset()
        }
    }

    /// Back to rest without animating: the second copy now sits where the
    /// first began, so the jump can't be seen.
    private func reset() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            offset = 0
            isScrolling = false
        }
    }
}
