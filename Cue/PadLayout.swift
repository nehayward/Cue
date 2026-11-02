import SwiftUI
import UIKit

/// Whether a window is laid out the iPad's way: the player's tight stack
/// with the queue (or a book's chapters) in the side panel and its toggle in
/// the navigation bar, the queue toggle in the mini player, the toasts drawn
/// at the window and the larger controls. Always on the iPad, the Mac and
/// Vision; on an iPhone only with regular width and height, which is the
/// iPhone Duo open. The Duo reports the phone idiom on both displays, so a
/// check of the idiom alone gave its inner display the iPhone's player
/// stretched across it, with a book's chapters in a sheet over it. Folded,
/// or sharing the inner display with another app, it's compact width and
/// the iPhone's again. A large iPhone in landscape is regular width but
/// compact height, and stays the iPhone's. Ported from Clic.
enum PadLayout {
    /// The iPad, the Mac and Vision, whatever the size classes. The idiom
    /// never changes while the app runs, so it's read once.
    static let alwaysActive = UIDevice.current.userInterfaceIdiom != .phone

    static func isActive(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) -> Bool {
        alwaysActive || (horizontal == .regular && vertical == .regular)
    }

    /// The foreground window's, for code outside a view (`CueApp`'s deep
    /// links). Views read `usesPadLayout` from the environment.
    static var isActive: Bool {
        guard !alwaysActive else { return true }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let traits = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.traitCollection
        return isActive(
            horizontal: traits.flatMap { UserInterfaceSizeClass($0.horizontalSizeClass) },
            vertical: traits.flatMap { UserInterfaceSizeClass($0.verticalSizeClass) }
        )
    }
}

extension EnvironmentValues {
    /// `PadLayout` for the window, set at its root by `withPadLayout()`. Read
    /// this rather than a view's own size class: a split view's sidebar
    /// column reports compact even in a full-width window.
    @Entry var usesPadLayout: Bool = PadLayout.alwaysActive
}

extension View {
    /// Sets `usesPadLayout` from the window's size classes for everything in
    /// it, the player's cover, the sheets and the queue panel included, so it
    /// goes outside their modifiers. The Duo changes it as it's folded and
    /// opened.
    func withPadLayout() -> some View {
        modifier(PadLayoutModifier())
    }
}

private struct PadLayoutModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func body(content: Content) -> some View {
        content
            .environment(\.usesPadLayout, PadLayout.isActive(horizontal: horizontalSizeClass, vertical: verticalSizeClass))
    }
}
