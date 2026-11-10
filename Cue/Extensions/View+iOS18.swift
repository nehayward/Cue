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

    /// A pull down past the top of the scroll view, as pull-to-refresh is
    /// (nothing before iOS 18): `onPull` once the drag has pulled it down
    /// more than `distance`, so what it brings up shows while the finger is
    /// still down, and `onRelease` as that drag lets go. What wants the
    /// keyboard waits for `onRelease`: the drag would dismiss it.
    @ViewBuilder
    func onPullDown(
        beyond distance: CGFloat,
        onPull: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            modifier(PullDownAction(distance: distance, onPull: onPull, onRelease: onRelease))
        } else {
            self
        }
    }
}

@available(iOS 18.0, *)
private struct PullDownAction: ViewModifier {
    let distance: CGFloat
    let onPull: () -> Void
    let onRelease: () -> Void
    /// A finger is dragging the scroll view.
    @State private var isDragging = false
    /// This drag has pulled past `distance` (and called `onPull`).
    @State private var hasPulled = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { scroll in
                // How far above its top the content has been pulled.
                scroll.contentOffset.y + scroll.contentInsets.top < -distance
            } action: { _, pulled in
                // Only a finger's pull: not the bounce back, nor a fling
                // landing on the top.
                guard pulled, isDragging, !hasPulled else { return }
                hasPulled = true
                onPull()
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                if newPhase == .interacting {
                    isDragging = true
                    hasPulled = false
                } else if oldPhase == .interacting {
                    isDragging = false
                    if hasPulled {
                        hasPulled = false
                        onRelease()
                    }
                }
            }
    }
}
