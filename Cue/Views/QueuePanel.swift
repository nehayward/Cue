import Defaults
import SwiftUI

/// The trailing queue panel, as an ordinary sibling view rather than
/// `.inspector` — in a regular-width window. In a compact one (iPhone, an
/// iPad slide-over) a side panel would leave a sliver of content next to a
/// sliver of queue, so the same view comes up as a sheet instead: half
/// height by default, with the view behind it still usable, full height on
/// a pull.
///
/// `.inspector` on Catalyst is a column of a UIKit split view — the same one
/// `.sidebarAdaptable` uses for the tab sidebar — so its width, its collapse
/// behaviour and its show/hide animation all belong to UIKit's column
/// balancing. An `HStack` sibling has none of that: the panel is exactly the
/// width given, it never competes with the sidebar for a column, and both the
/// transition and the resize gesture are ours.
struct QueuePanel<Panel: View>: ViewModifier {
    /// What a compact width does with the panel.
    enum CompactBehavior {
        /// A half-height sheet over the content.
        case sheet
        /// Nothing: the queue lives somewhere else at this width (the main
        /// window's, which the player presents on iPhone).
        case hidden
    }

    @Binding var isPresented: Bool
    var compactBehavior: CompactBehavior = .sheet
    @ViewBuilder var panel: () -> Panel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var wantsSheet: Bool { isCompact && compactBehavior == .sheet }

    /// The sheet's own visibility, kept apart from `isPresented`. A window
    /// changing size class (an iPad going in or out of multitasking) takes
    /// a presented sheet down, and SwiftUI reports that through the binding
    /// as if the person had swiped it away — bound straight to
    /// `isPresented`, the queue then stayed hidden once the width came back.
    /// With its own state the sheet can come and go with the width while the
    /// person's choice holds, and only a dismissal made while the window is
    /// standing still counts as theirs.
    @State private var sheetShown = false
    /// When the window last changed size. A sheet dismissal within a
    /// moment of it is the resize's doing, not the person's.
    @State private var lastResize: Date = .distantPast

    private static var resizeGrace: TimeInterval { 1 }

    static var minWidth: CGFloat { 260 }
    static var maxWidth: CGFloat { 520 }
    /// What the panel refuses to take from the rest of the window: the sidebar
    /// plus a content column still worth looking at. Without this the panel
    /// keeps its stored width as the window narrows and the tab content is the
    /// only thing that gives, down to a few points of vertically-wrapped text.
    static var minContentWidth: CGFloat { 600 }

    @AppStorage(AppStorageKeys.queuePanelWidth) private var storedWidth: Double = 320
    /// The width while a drag is in flight. `storedWidth` is `UserDefaults` —
    /// writing it per drag frame means a synchronous write plus a defaults
    /// notification on every frame, which is what made the resize feel sticky.
    /// The drag runs entirely on this, and commits once on release.
    @State private var dragWidth: CGFloat?
    /// Width at the moment the drag began. Resizing from the live width instead
    /// compounds each frame's translation against the previous frame's result,
    /// which accelerates away from the cursor.
    @State private var widthAtDragStart: CGFloat?
    @State private var isHoveringDivider = false
    /// How far past the panel's minimum width the divider has been dragged
    /// toward the trailing edge. The panel slides out by this much, and past
    /// `dismissDistance` letting go dismisses it.
    @State private var dismissOvershoot: CGFloat = 0

    static var dismissDistance: CGFloat { 72 }
    /// The whole window's width — this modifier sits on the `TabView`, so the
    /// `HStack` spans it.
    @State private var availableWidth: CGFloat?

    private var width: CGFloat {
        min(clamped(dragWidth ?? CGFloat(storedWidth)), widthCeiling)
    }

    /// The panel yields first when the window gets narrow, rather than letting
    /// the content column be squeezed to nothing. Never below `minWidth` —
    /// past that point the window itself is at its minimum size.
    private var widthCeiling: CGFloat {
        guard let availableWidth else { return Self.maxWidth }
        return max(Self.minWidth, availableWidth - Self.minContentWidth)
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.minWidth), Self.maxWidth)
    }

    // An `HStack` sibling rather than a trailing `safeAreaInset`: an inset
    // leaves the modified view at full width, so the tab bar accessory stays
    // centred on the whole window and slides under the panel. Taking real
    // width away is what keeps the play bar centred on the content.
    // One structure whatever the width — the side panel and the sheet are
    // both always attached and each is empty when the other applies — so a
    // size-class change (an iPad going into multitasking) doesn't rebuild
    // `content`, which is the whole tab view.
    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            content

            if isPresented, !isCompact {
                // Divider and panel transition as one unit. As separate
                // children of the `HStack` they each got their own transition:
                // the panel slid in from the trailing edge while the divider,
                // having none of its own, fell back to a fade and appeared in
                // place. `geometryGroup` keeps the pair's frames resolving
                // together rather than each animating independently.
                HStack(spacing: 0) {
                    divider
                    panel()
                        .frame(width: width)
                        .modifier(PanelBackground())
                        .padding(.trailing, 10)
                        .padding(.vertical, 10)
                }
                // Down to the window's bottom edge rather than stopping above
                // the tab bar accessory's inset.
                .ignoresSafeArea(.container, edges: .bottom)
                // Following the finger past the minimum width: the pair moves
                // off the edge, dimming as it goes, so a drag to dismiss reads
                // as one before it lands.
                .offset(x: dismissOvershoot)
                .opacity(1 - min(1, dismissOvershoot / Self.dismissDistance) * 0.5)
                .geometryGroup()
                // Clipped so the pair slides out from under its own edge
                // rather than overhanging the window during the move.
                .clipped()
                .transition(.move(edge: .trailing))
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            if availableWidth != nil, availableWidth != newWidth {
                lastResize = .now
            }
            availableWidth = newWidth
        }
        .animation(.snappy, value: isPresented)
        // The person's choice, or the width, changed: the sheet follows.
        .onChange(of: wantsSheet, initial: true) { _, wants in
            lastResize = .now
            sheetShown = wants && isPresented
        }
        .onChange(of: isPresented) { _, presented in
            sheetShown = wantsSheet && presented
        }
        // The sheet went down. Theirs, or the window's?
        .onChange(of: sheetShown) { _, shown in
            guard !shown, isPresented else { return }
            if Date.now.timeIntervalSince(lastResize) < Self.resizeGrace {
                // The resize took it. Put it back once the layout settles,
                // if this width still wants one; a regular width shows the
                // side panel from the same flag instead.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    if isPresented, wantsSheet, !sheetShown {
                        sheetShown = true
                    }
                }
            } else {
                isPresented = false
            }
        }
        .sheet(isPresented: $sheetShown) {
            panel()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                // No `presentationBackground`: the system's own sheet
                // background is Liquid Glass, and naming a material here
                // replaces it with a flat blur.
                // The player stays usable under the half-height sheet — the
                // queue is something you glance at while the music plays.
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    /// A hairline with a much wider invisible hit area — a 1pt drag target is
    /// unhittable in practice — plus a grab handle that fades in on hover.
    private var divider: some View {
        Capsule()
            .fill(.secondary)
            .frame(width: 4, height: 32)
            // Faintly visible at rest rather than hidden: there's no hover on
            // iPad, so a handle that only appears on hover is a drag target
            // nobody can find.
            .opacity(isHoveringDivider || widthAtDragStart != nil ? 1 : 0.35)
            .frame(width: 16)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .onHover { isHoveringDivider = $0 }
            .gesture(
                // `minimumDistance: 0` so the first pixel of movement resizes.
                // Any threshold hands those pixels to the scroll views either
                // side, which read the drag as a scroll and swallow it.
                // `.global`, not the default `.local`. The divider moves as a
                // result of its own drag, and in local space that movement is
                // folded back into `translation` on the next frame — the
                // handle chases the finger and the width oscillates. Global
                // space doesn't move with the view, so the translation is
                // purely how far the finger went.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let start = widthAtDragStart ?? width
                        widthAtDragStart = start
                        // Trailing panel: dragging left (negative) widens it.
                        // Rounded to whole points — sub-pixel changes re-lay out
                        // the entire tab content for no visible difference.
                        let proposed = (start - value.translation.width).rounded()
                        dragWidth = clamped(proposed)
                        // Past the minimum the width stops but the finger
                        // doesn't: the rest of the drag is toward dismissal.
                        dismissOvershoot = max(0, Self.minWidth - proposed)
                    }
                    .onEnded { _ in
                        if dismissOvershoot >= Self.dismissDistance {
                            // Off the edge: the drag was a dismissal. The
                            // stored width is left alone, so the panel comes
                            // back at the size it had.
                            withAnimation(.snappy) {
                                isPresented = false
                            }
                        } else if let dragWidth {
                            storedWidth = Double(dragWidth)
                        }
                        withAnimation(.snappy) {
                            dismissOvershoot = 0
                        }
                        widthAtDragStart = nil
                        dragWidth = nil
                    }
            )
            .animation(.easeOut(duration: 0.15), value: isHoveringDivider)
    }
}

/// The side panel's card: a flat material. Not Liquid Glass — the glass
/// draws its own drop shadow, which lifted the panel off the window.
private struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }
}

extension View {
    /// Shows `panel` alongside this view in a regular width — sliding in from
    /// the trailing edge, resizable by dragging the divider between the two —
    /// and as a sheet in a compact one, unless `compact` says to leave it out.
    func queuePanel<Panel: View>(
        isPresented: Binding<Bool>,
        compact: QueuePanel<Panel>.CompactBehavior = .sheet,
        @ViewBuilder panel: @escaping () -> Panel
    ) -> some View {
        modifier(QueuePanel(isPresented: isPresented, compactBehavior: compact, panel: panel))
    }
}
