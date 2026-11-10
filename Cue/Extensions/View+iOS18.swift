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
}
