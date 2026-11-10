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

    /// Runs `action` when the scroll view is let go of while pulled down
    /// past its top by more than `distance`, once a pull (nothing before
    /// iOS 18). On letting go rather than as the pull gets there, so what
    /// it opens (a field taking the keyboard) comes after the drag, which
    /// would dismiss the keyboard.
    @ViewBuilder
    func onPullDown(
        beyond distance: CGFloat,
        perform action: @escaping () -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            modifier(PullDownAction(distance: distance, action: action))
        } else {
            self
        }
    }
}

@available(iOS 18.0, *)
private struct PullDownAction: ViewModifier {
    let distance: CGFloat
    let action: () -> Void
    /// Pulled down past `distance` right now.
    @State private var isPulled = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { scroll in
                scroll.contentOffset.y + scroll.contentInsets.top < -distance
            } action: { _, pulled in
                isPulled = pulled
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                // Let go, still pulled that far: not pushed back first.
                guard oldPhase == .interacting, newPhase != .interacting, isPulled else { return }
                action()
            }
    }
}
