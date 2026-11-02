import SwiftUI
import UIKit

/// The Mac window's measures and colours (`DesktopShell`): rounded cards on
/// the window's background, after DaftMusic and Spotify. In points of the
/// iPad idiom the Mac app runs in, which macOS draws at 77%, so they're a
/// third larger than the same thing in a native Mac app.
enum DesktopStyle {
    /// Round the window's edges and between cards.
    static let gap: CGFloat = 12
    /// Above the cards: room for the traffic lights, which sit over the
    /// sidebar's top corner, and a strip to drag the window by.
    static let topInset: CGFloat = 36
    static let cornerRadius: CGFloat = 22
    static let sidebarWidth: CGFloat = 300
    /// The search row above the content.
    static let toolbarHeight: CGFloat = 48
    /// The player cards along the bottom.
    static let barHeight: CGFloat = 76
    /// Below this the queue card gives way, then the sidebar narrows.
    static let queueMinWindowWidth: CGFloat = 1180

    /// The window behind the cards: the content's own (the lists' black or
    /// white), so a page sits on it with no card of its own, as DaftMusic's
    /// does.
    static let windowBackground = Color(uiColor: .systemBackground)
    /// The sidebar, the queue, the search field and the player cards.
    static let card = Color(uiColor: .secondarySystemBackground)
    /// Under a row or button the pointer is over.
    static let hover = Color.primary.opacity(0.07)
    /// Under the chosen sidebar row.
    static let selection = Color.primary.opacity(0.1)

    /// How much larger than its base a measure draws at this type size
    /// (`InterfaceSize`): the body text's size over its default 17 pt, so
    /// a card grows with the text in it.
    static func scale(_ typeSize: DynamicTypeSize) -> CGFloat {
        let body: CGFloat = switch typeSize {
        case .xSmall: 14
        case .small: 15
        case .medium: 16
        case .large: 17
        case .xLarge: 19
        case .xxLarge: 21
        case .xxxLarge: 23
        default: 25
        }
        return body / 17
    }
}

extension View {
    /// A card: the shell's grey, rounded.
    func desktopCard(cornerRadius: CGFloat = DesktopStyle.cornerRadius) -> some View {
        background(DesktopStyle.card, in: .rect(cornerRadius: cornerRadius))
    }

    /// A rounded wash under the view while the pointer is over it.
    func desktopHover(cornerRadius: CGFloat = 10, isSelected: Bool = false) -> some View {
        modifier(DesktopHoverHighlight(cornerRadius: cornerRadius, isSelected: isSelected))
    }

    /// Grows a little under the pointer, as a cover does in Music: for
    /// artwork and tiles that are buttons in themselves.
    func desktopHoverLift(scale: CGFloat = 1.03) -> some View {
        modifier(DesktopHoverLift(scale: scale))
    }
}

private struct DesktopHoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    let isSelected: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isSelected ? DesktopStyle.selection : DesktopStyle.hover)
                    .opacity(isSelected || isHovering ? 1 : 0)
            }
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct DesktopHoverLift: ViewModifier {
    let scale: CGFloat
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            // A scale alone: a shadow is drawn offscreen, which on the Mac
            // costs GPU memory for as long as it animates.
            .scaleEffect(isHovering ? scale : 1)
            .onHover { isHovering = $0 }
            .animation(.snappy(duration: 0.18), value: isHovering)
    }
}

/// A round glyph button: a wash under the pointer, and a press that sinks.
/// The player cards' transport and actions, and the toolbar's Back and
/// Forward.
struct DesktopIconButtonStyle: ButtonStyle {
    var side: CGFloat = 40
    /// Filled with the card's grey when not under the pointer (the toolbar's
    /// Back and Forward, which sit on the window rather than a card).
    var isFilled = false

    func makeBody(configuration: Configuration) -> some View {
        DesktopIconButton(configuration: configuration, side: side, isFilled: isFilled)
    }
}

private struct DesktopIconButton: View {
    let configuration: ButtonStyle.Configuration
    let side: CGFloat
    let isFilled: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var isHovering = false

    var body: some View {
        let side = (side * DesktopStyle.scale(typeSize)).rounded()

        configuration.label
            .frame(width: side, height: side)
            .background {
                Circle()
                    .fill(isFilled ? DesktopStyle.card : .clear)
                Circle()
                    .fill(DesktopStyle.hover)
                    .opacity(isHovering && isEnabled ? 1 : 0)
            }
            .contentShape(.circle)
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .onHover { isHovering = $0 }
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
