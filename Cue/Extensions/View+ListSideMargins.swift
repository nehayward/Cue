import SwiftUI

extension View {
    /// A list's sides, `length` points in (the library lists' 16), counted
    /// from the safe area rather than from the list's own edges.
    ///
    /// `contentMargins` on a `List` place its inset-grouped sections from the
    /// list's edges, which run under a safe area at the side, while the rows'
    /// content keeps out of it. With one there, an iPhone Duo open, whose
    /// status bar, navigation bar and tab bar run down the trailing edge, a
    /// section's card went on under them, its rows under the toolbar's
    /// buttons and wider than the rows and cards around it. Without a safe
    /// area at the sides (an iPhone, an iPad, the Mac) nothing changes. A
    /// `ScrollView` counts its margins from the safe area already: give it
    /// `contentMargins`.
    func listSideMargins(_ length: CGFloat = 16, for placement: ContentMarginPlacement = .automatic) -> some View {
        modifier(ListSideMargins(length: length, placement: placement))
    }
}

private struct ListSideMargins: ViewModifier {
    let length: CGFloat
    let placement: ContentMarginPlacement

    @State private var sides = SideInsets()

    func body(content: Content) -> some View {
        content
            .contentMargins(.leading, length + sides.leading, for: placement)
            .contentMargins(.trailing, length + sides.trailing, for: placement)
            // Read from a view that reaches under the safe area, which is
            // given the insets it reaches into.
            .background {
                Color.clear
                    .onGeometryChange(for: SideInsets.self) { proxy in
                        SideInsets(leading: proxy.safeAreaInsets.leading, trailing: proxy.safeAreaInsets.trailing)
                    } action: { sides = $0 }
                    .ignoresSafeArea()
            }
    }
}

/// The safe area at the two sides, compared so a change of the top or
/// bottom (a bar shrinking on scroll) doesn't set the margins again.
private struct SideInsets: Equatable {
    var leading: CGFloat = 0
    var trailing: CGFloat = 0
}
