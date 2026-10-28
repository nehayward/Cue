import SwiftUI

extension View {
    /// The library lists' sides: 16 points, except on an iPhone Duo open,
    /// where they're the system's own.
    ///
    /// `contentMargins` on a `List` place its inset-grouped sections from
    /// the list's edges, which run under a safe area at the side, while the
    /// rows' content keeps out of it. The Duo open has one, its status bar,
    /// navigation bar and tab bar running down the trailing edge, so with 16
    /// points a section's card went on under them, its rows under the
    /// toolbar's buttons. The system's margins (`nil`) keep out of the safe
    /// area. No other device has a safe area at the sides, so the iPhone,
    /// iPad and the Mac keep 16.
    func librarySideMargins(for placement: ContentMarginPlacement = .automatic) -> some View {
        modifier(LibrarySideMargins(placement: placement))
    }
}

private struct LibrarySideMargins: ViewModifier {
    let placement: ContentMarginPlacement

    @Environment(\.usesPadLayout) private var usesPadLayout

    /// The phone idiom in the iPad's layout (`PadLayout`).
    private var isDuoOpen: Bool {
        usesPadLayout && UIDevice.current.userInterfaceIdiom == .phone
    }

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, isDuoOpen ? nil : 16, for: placement)
    }
}
