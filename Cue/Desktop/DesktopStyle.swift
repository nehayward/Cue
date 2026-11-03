import SwiftUI
import UIKit

/// The Mac window's measures and colours (`DesktopShell`): full-height
/// panels down its sides and a floating player bar, as macOS 27's Music
/// has. In points of the iPad idiom the Mac app runs in, which macOS draws
/// at 77%, so they're a third larger than the same thing in a native Mac
/// app.
enum DesktopStyle {
    static let sidebarWidth: CGFloat = 300
    /// The title bar's strip at the top of a panel, the traffic lights in
    /// the sidebar's: its rows start below it. Left to the safe area, a
    /// panel's list ran up under the lights. Not scaled, as the title bar
    /// isn't.
    static let titleBarHeight: CGFloat = 36
    /// The player's bar, floating over the foot of the page.
    static let barHeight: CGFloat = 72
    /// Between the bar and the page's sides and foot.
    static let barMargin: CGFloat = 16
    /// Below this the queue gives way, then the sidebar narrows.
    static let queueMinWindowWidth: CGFloat = 1180

    /// Behind the page: the content's own (the lists' black or white).
    static let windowBackground = Color(uiColor: .systemBackground)
    /// The sidebar and the queue.
    static let panel = Color(uiColor: .secondarySystemBackground)
    /// Where a panel meets the page.
    static let panelEdge = Color.primary.opacity(0.08)
    /// Under a row or button the pointer is over.
    static let hover = Color.primary.opacity(0.07)
    /// Under the chosen sidebar row.
    static let selection = Color.primary.opacity(0.1)

    /// How much larger than its base a measure draws at this type size
    /// (`InterfaceSize`): the body text's size over its default 17 pt, so
    /// a panel grows with the text in it.
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
    /// A panel down a side of the window (the queue): the shell's grey up
    /// through the title bar, with a hairline on the `edge` it meets the
    /// page by, and the view below the title bar's strip.
    func desktopPanel(edge: HorizontalEdge) -> some View {
        belowTitleBar()
            .desktopPanelBackground(edge: edge)
    }

    /// The panels' grey up through the title bar, with a hairline on the
    /// `edge` it meets the page by. Not the sidebar's on the Mac, which is
    /// macOS's own material (`DesktopSplit`).
    func desktopPanelBackground(edge: HorizontalEdge) -> some View {
        background {
            DesktopStyle.panel
                .overlay(alignment: edge == .leading ? .leading : .trailing) {
                    DesktopStyle.panelEdge
                        .frame(width: 1)
                }
                .ignoresSafeArea()
        }
    }

    /// The view below the title bar's strip, which a panel's list ran up
    /// under, behind the traffic lights, when left to the safe area.
    func belowTitleBar() -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: DesktopStyle.titleBarHeight)
            self
        }
        .ignoresSafeArea(.container, edges: .top)
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
/// The player bar's transport and actions, and the sidebar's gear.
struct DesktopIconButtonStyle: ButtonStyle {
    var side: CGFloat = 40
    /// Filled with the panels' grey when not under the pointer, for a button
    /// on the page rather than a panel.
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
                    .fill(isFilled ? DesktopStyle.panel : .clear)
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
