import SwiftUI

/// How large the Mac's window draws: Cue's own scale, in place of the
/// system's "Optimize Interface for Mac". macOS draws an iPad app at 77%,
/// which left Cue's text and controls a size smaller than a Mac app's; each
/// step here is a Dynamic Type size for the whole window, its sheets and
/// the player (set at the window's root, `CueApp`), and the shell's cards
/// grow with it (`DesktopStyle.scale`). Text, symbols and layout are drawn
/// at the new size rather than magnified, so they stay sharp, and it costs
/// nothing once drawn.
enum InterfaceSize: String, CaseIterable, Identifiable {
    /// The iPad's own size, as the window drew before.
    case small
    /// A step up, about a Mac app's size: the default.
    case standard
    case large
    case extraLarge

    var id: Self { self }

    var title: String {
        switch self {
        case .small: "Small"
        case .standard: "Default"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    var typeSize: DynamicTypeSize {
        switch self {
        case .small: .large
        case .standard: .xLarge
        case .large: .xxLarge
        case .extraLarge: .xxxLarge
        }
    }

    /// The next size up or down, for View ▸ Bigger and Smaller; nil at
    /// either end.
    var bigger: InterfaceSize? {
        let all = Self.allCases
        let index = all.firstIndex(of: self)!
        return index + 1 < all.count ? all[index + 1] : nil
    }

    var smaller: InterfaceSize? {
        let all = Self.allCases
        let index = all.firstIndex(of: self)!
        return index > 0 ? all[index - 1] : nil
    }
}

extension View {
    /// The Mac window's size (`InterfaceSize`), at the window's root so the
    /// sheets and the player presented from it follow. Nothing elsewhere:
    /// iPhone and iPad follow the system's text size.
    func interfaceSize(_ size: InterfaceSize) -> some View {
        modifier(InterfaceSizeModifier(size: size))
    }
}

private struct InterfaceSizeModifier: ViewModifier {
    let size: InterfaceSize

    func body(content: Content) -> some View {
        if AppState.usesDesktopShell {
            content.dynamicTypeSize(size.typeSize)
        } else {
            content
        }
    }
}
