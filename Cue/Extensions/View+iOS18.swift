import SwiftUI

extension View {
    /// Updates `isActive` when the scroll view's vertical content offset
    /// crosses the given threshold.
    @ViewBuilder
    func onScrollOffset(
        exceeds threshold: CGFloat,
        set isActive: Binding<Bool>
    ) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: Bool.self) { scroll in
                scroll.contentOffset.y > threshold
            } action: { _, newValue in
                isActive.wrappedValue = newValue
            }
        } else {
            self
        }
    }

    /// A pull down past the top of the scroll view that brings something up,
    /// as pull-to-refresh does (nothing before iOS 18): `reveal` follows the
    /// finger's pull, turns `isShown` on once it's past the reveal's
    /// `distance`, and `onRelease` runs as that drag lets go. What wants the
    /// keyboard waits for `onRelease`: the drag would dismiss it. With
    /// `isEnabled` off it does nothing.
    @ViewBuilder
    func pullDownReveal(
        _ reveal: PullReveal,
        isEnabled: Bool = true,
        onRelease: @escaping () -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            modifier(PullRevealAction(reveal: reveal, isEnabled: isEnabled, onRelease: onRelease))
        } else {
            self
        }
    }
}

/// What a pull down past the top of a scroll view brings up (a playlist's
/// Find in Playlist bar): how far a finger has it pulled, and whether it's
/// up. Only what it brings up reads it, so a pull redraws that, every frame
/// the finger moves, and never the page around it: the bar came up as a
/// state change of the page's, which redrew the whole song list mid-pull,
/// and as a timed animation the finger didn't drive, and the pull jittered.
@MainActor @Observable
final class PullReveal {
    /// How far a pull goes to bring it up.
    let distance: CGFloat
    /// How far past its top a finger has the scroll view pulled, followed
    /// back as it lets go; 0 for any other overscroll (a fling landing on
    /// the top).
    var pull: CGFloat = 0
    /// It's up: pulled far enough, or put up by a button.
    var isShown = false

    /// From 0, none of it showing, to 1, all of it.
    var progress: CGFloat {
        isShown ? 1 : min(max(pull / distance, 0), 1)
    }

    /// Puts it away (left empty, or closed). The drag under way, or one
    /// starting with this, can't bring it back: a drag down the list that
    /// dismissed the keyboard, and the empty bar with it, pulled on past
    /// the top and brought the bar straight back up, and the keyboard with
    /// it as it let go.
    func hide() {
        isShown = false
        hiddenAt = .now
        if isDragging { revealsThisDrag = false }
    }

    // The pull under way, which nothing draws.
    /// A finger is dragging the scroll view.
    @ObservationIgnored fileprivate var isDragging = false
    /// This drag may bring it up: it started with it put away, and didn't
    /// put it away itself.
    @ObservationIgnored fileprivate var revealsThisDrag = false
    /// When `hide()` last put it away.
    @ObservationIgnored fileprivate var hiddenAt: Date?
    /// This drag pulled past the top: `pull` follows it until the scroll
    /// view comes to rest.
    @ObservationIgnored fileprivate var followsPull = false
    /// This drag brought it up, so its release calls `onRelease`.
    @ObservationIgnored fileprivate var broughtUp = false

    init(distance: CGFloat) {
        self.distance = distance
    }
}

@available(iOS 18.0, *)
private struct PullRevealAction: ViewModifier {
    let reveal: PullReveal
    let isEnabled: Bool
    let onRelease: () -> Void

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { scroll in
                // How far above its top the content is pulled; 0 whenever
                // it isn't, so scrolling the list never calls the action.
                max(0, -(scroll.contentOffset.y + scroll.contentInsets.top))
            } action: { _, pull in
                guard isEnabled else { return }
                // Only a finger's pull, and the bounce back from it: not a
                // fling landing on the top.
                if reveal.isDragging, reveal.revealsThisDrag, pull > 0 {
                    reveal.followsPull = true
                }
                let followed = reveal.followsPull ? pull : 0
                // An @Observable property notifies on every write.
                if reveal.pull != followed {
                    reveal.pull = followed
                }
                if reveal.isDragging, reveal.revealsThisDrag, pull >= reveal.distance, !reveal.isShown {
                    reveal.isShown = true
                    reveal.broughtUp = true
                }
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                guard isEnabled else { return }
                if newPhase == .interacting {
                    reveal.isDragging = true
                    reveal.broughtUp = false
                    // Not the drag whose start dismissed the keyboard and
                    // put it away: which of the two comes first varies, so
                    // a `hide()` a moment ago counts as this drag's.
                    let justHidden = reveal.hiddenAt.map { Date.now.timeIntervalSince($0) < 0.3 } ?? false
                    reveal.revealsThisDrag = !reveal.isShown && !justHidden
                } else if oldPhase == .interacting {
                    reveal.isDragging = false
                    if reveal.broughtUp {
                        reveal.broughtUp = false
                        onRelease()
                    }
                }
                if newPhase == .idle {
                    reveal.followsPull = false
                    if reveal.pull != 0 {
                        reveal.pull = 0
                    }
                }
            }
    }
}
