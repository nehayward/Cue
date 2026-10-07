import OSLog
import SwiftUI
import SonosKit
import VibesDS
import UIKit

/// The app's toast: a capsule at the top of the screen with the alert's
/// artwork, text and symbol.
///
/// Where its host reaches the top of an upright iPhone with a Dynamic Island
/// (the tabs, the player), it grows out of the island the way a Live
/// Activity expands: a black capsule that starts inside the island's
/// outline, where the island hides it, opens out across the screen with its
/// content below the island, and closes back into it when it goes. The
/// status bar steps aside meanwhile, as it does for the island's own. Cue
/// can't draw in the island itself (the system owns it), but black over
/// black reads as one shape.
///
/// Everywhere else (a sheet, landscape, an iPhone without an island, iPad,
/// the Mac) it's a glass capsule that drops in from the top edge.
///
/// Several screens host one (`withAlert()`); only the one that appeared last
/// draws it (`AlertService.frontHost`), so a sheet's doesn't show it a second
/// time over the screen behind.
struct AlertView: View {
    @Environment(AlertService.self) private var alertService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var id = UUID()
    @State private var host = HostGeometry()
    /// How far the capsule is being dragged. Up follows the finger and puts
    /// it away; down gives a little, then stops.
    @State private var drag: CGFloat = 0

    private var alert: Alert { alertService.alert }

    var body: some View {
        let island = DynamicIsland.frame(in: host.frame)
        ZStack(alignment: .top) {
            if alert.isShowing, alertService.frontHost == id {
                if let island {
                    islandCapsule(island)
                } else {
                    glassCapsule
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: HostGeometry.self) { proxy in
            HostGeometry(frame: proxy.frame(in: .global), safeTop: proxy.safeAreaInsets.top)
        } action: { host = $0 }
        // Out to the host's top edge, so the island's capsule can be placed
        // in screen points and the check above can tell whether this host
        // starts at the top of the screen.
        .ignoresSafeArea(.container, edges: .top)
        // Opens with a little bounce, as the island does; closes without.
        .animation(alert.isShowing ? .bouncy(duration: 0.5, extraBounce: 0.05) : .smooth(duration: 0.35), value: alert.isShowing)
        // In line while it's in a window, not between onAppear and
        // onDisappear: a sheet closed by a play (Search, an album) as the
        // player came up could stay in line, and the player's host never
        // drew the alert.
        .background(alignment: .topLeading) {
            HostWindowProbe { isInWindow in
                if isInWindow {
                    alertService.addHost(id)
                } else {
                    alertService.removeHost(id)
                }
            }
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
        }
#if DEBUG
        .onChange(of: alert.isShowing) { _, isShowing in
            guard isShowing else { return }
            let name = String(id.uuidString.prefix(4))
            let isFront = alertService.frontHost == id
            let style = island.map { "island \($0)" } ?? "glass"
            Self.log.debug("host \(name, privacy: .public): front \(isFront), \(style, privacy: .public)")
        }
#endif
    }

    private static let log = Logger(subsystem: "dance.cue", category: "alert")
}

// MARK: - Capsules

private extension AlertView {
    /// The capsule grown out of the island: as wide as the screen less the
    /// island's distance from its top on either side, with the island in a
    /// band across its top and the alert below it.
    func islandCapsule(_ island: CGRect) -> some View {
        let outline = CGSize(width: island.width - 2 * IslandMorph.inset, height: island.height - 2 * IslandMorph.inset)
        return VStack(spacing: 6) {
            Color.clear
                .frame(height: island.height)
            row(fills: true)
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
        }
        .frame(width: min(host.frame.width - 2 * island.minY, 440))
        .environment(\.colorScheme, .dark)
        .contentShape(.capsule)
        .modifier(AlertInteraction(alertService: alertService, drag: $drag))
        .transition(AnyTransition.modifier(
            active: IslandMorph(outline: outline, phase: reduceMotion ? .faded : .closed),
            identity: IslandMorph(outline: outline, phase: .open)
        ))
        // Pushed up, it shrinks back toward the island.
        .scaleEffect(drag < 0 ? max(0.8, 1 + drag / 300) : 1 + pull / 600, anchor: .top)
        .padding(.top, island.minY)
        .hidesStatusBar()
    }

    /// The capsule everywhere else, sized to what it says.
    var glassCapsule: some View {
        row(fills: false)
            .padding(.leading, alert.content == nil ? 18 : 10)
            .padding(.trailing, 20)
            .padding(.vertical, 10)
            .alertGlass(interactive: alert.handleTap != nil)
            .contentShape(.capsule)
            .modifier(AlertInteraction(alertService: alertService, drag: $drag))
            .frame(maxWidth: 440)
            .transition(
                reduceMotion
                    ? AnyTransition.opacity
                    : AnyTransition.offset(y: -24).combined(with: .scale(scale: 0.85, anchor: .top)).combined(with: .opacity)
            )
            .offset(y: drag < 0 ? drag : pull)
            .padding(.top, host.safeTop + 8)
            .padding(.horizontal, 16)
    }

    /// The artwork, then the text, with the symbol (or the spinner while
    /// something's on its way to a speaker) at the end. Without artwork the
    /// symbol leads, as in the system's own banners.
    func row(fills: Bool) -> some View {
        HStack(spacing: 12) {
            if let content = alert.content {
                VibeContentArtworkView(content: content, showMusicSource: false)
                    .frame(width: 40, height: 40)
            } else {
                accessory
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(alert.text)
                    .font(.subheadline.weight(.semibold))
                if alert.subtitle != "" {
                    Text(alert.subtitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(2)
            if fills {
                Spacer(minLength: 0)
            }
            if alert.content != nil {
                accessory
            }
        }
        .fontDesign(.rounded)
        .animation(.smooth, value: alert.text)
    }

    @ViewBuilder
    var accessory: some View {
        if alert.isLoading {
            ProgressView()
                .tint(.secondary)
        } else if let imageName = alert.imageName, !imageName.isEmpty {
            Image(systemName: imageName)
                .font(.title3.weight(.semibold))
        }
    }

    /// A downward drag, damped so it gives about 12 points at most.
    var pull: CGFloat {
        drag > 0 ? 12 * (1 - exp(-drag / 60)) : 0
    }
}

// MARK: - Interaction

/// Tap to act, swipe up (or VoiceOver's escape) to put it away.
private struct AlertInteraction: ViewModifier {
    let alertService: AlertService
    @Binding var drag: CGFloat

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { drag = $0.translation.height }
                    .onEnded { value in
                        if value.translation.height < -30 || value.predictedEndTranslation.height < -80 {
                            alertService.dismiss()
                        }
                        withAnimation(.snappy) {
                            drag = 0
                        }
                    }
            )
            .onTapGesture {
                alertService.alert.handleTap?()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(alertService.alert.handleTap == nil ? [] : .isButton)
            .accessibilityAction(.escape) {
                alertService.dismiss()
            }
    }
}

// MARK: - Island

/// The island opening out into the capsule, as a transition: inserted, the
/// capsule starts as a smaller copy of the island's outline and grows to its
/// own size, its content fading in as it does; removed, it closes back in.
private struct IslandMorph: ViewModifier {
    enum Phase {
        case open
        /// Inside the island's outline.
        case closed
        /// At full size but transparent, for Reduce Motion.
        case faded
    }

    /// How far inside the island's outline the closed capsule sits, so it
    /// stays hidden behind the island if the island is a point or two off
    /// where `DynamicIsland` puts it.
    static let inset: CGFloat = 4

    let outline: CGSize
    let phase: Phase

    func body(content: Content) -> some View {
        let isClosed = phase == .closed
        content
            .opacity(phase == .open ? 1 : 0)
            .blur(radius: isClosed ? 6 : 0)
            .scaleEffect(isClosed ? 0.8 : 1, anchor: .top)
            .frame(width: isClosed ? outline.width : nil, height: isClosed ? outline.height : nil, alignment: .top)
            .background(.black, in: .capsule)
            .clipShape(.capsule)
            .offset(y: isClosed ? Self.inset : 0)
            .opacity(phase == .faded ? 0 : 1)
    }
}

/// Where the Dynamic Island is, for the alert to grow out of.
private enum DynamicIsland {
    /// The island's outline in a host's coordinates, or nil when there's
    /// none to grow out of: the host doesn't start at the top of the screen
    /// (a sheet), the phone has no island or is on its side, or this isn't
    /// a phone. There's no API for the island's frame, so it's worked out
    /// from the top safe area.
    @MainActor
    static func frame(in host: CGRect) -> CGRect? {
#if os(iOS) && !targetEnvironment(macCatalyst)
        guard UIDevice.current.userInterfaceIdiom == .phone, let window = Self.window else { return nil }
        let bounds = window.bounds
        guard bounds.height > bounds.width,
              abs(host.minY) < 1, abs(host.minX) < 1, abs(host.width - bounds.width) < 1
        else { return nil }
        // Read while the status bar is up, and kept for while the capsule
        // has it hidden, which may change the safe area: worked out live
        // then, the island could move, or go and take the capsule (and the
        // hidden status bar) with it, over and over.
        let top: CGFloat
        if window.windowScene?.statusBarManager?.isStatusBarHidden == true, let kept = topInsets[bounds.width] {
            top = kept
        } else {
            top = window.safeAreaInsets.top
            topInsets[bounds.width] = top
        }
        // An island's iPhone insets the top by 59 points or more, a notched
        // one by 44 to 50.
        guard top > 52 else { return nil }
        // 126 × 37 points, ending 11 above the safe area: 11 from the top
        // on the iPhone 14 Pro, 15 and 16 (59-point inset), 14 on the 16 Pro
        // and 17 (62), whose island sits lower.
        let size = CGSize(width: 126, height: 37)
        return CGRect(x: (bounds.width - size.width) / 2, y: top - 48, width: size.width, height: size.height)
#else
        return nil
#endif
    }

#if os(iOS) && !targetEnvironment(macCatalyst)
    /// The top safe area by window width, as last read with the status bar up.
    @MainActor
    private static var topInsets: [CGFloat: CGFloat] = [:]

    @MainActor
    private static var window: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow ?? scene?.windows.first
    }
#endif
}

/// Tells a host when it joins or leaves a window. UIKit always says: a
/// sheet's views leave when it closes, a tab's when another is chosen, and
/// the screen's under a full-screen cover while it's up.
private struct HostWindowProbe: UIViewRepresentable {
    let onChange: (Bool) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onChange = onChange
    }

    final class ProbeView: UIView {
        var onChange: ((Bool) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // After the update that moved it, not during it, and as things
            // stand then: a view moved within the window leaves and joins in
            // one go, which shouldn't count as joining again. A view freed
            // meanwhile (a closed sheet's) has left.
            let onChange = onChange
            DispatchQueue.main.async { [weak self] in
                onChange?(self?.window != nil)
            }
        }
    }
}

/// Where a host is in the window, out to its top edge, and how much of that
/// is under the status bar.
private struct HostGeometry: Equatable {
    var frame: CGRect = .zero
    var safeTop: CGFloat = 0
}

private extension View {
    /// The island's capsule covers the status bar's clock and icons, so
    /// they step aside while it's out, as they do for the island's own.
    @ViewBuilder
    func hidesStatusBar() -> some View {
#if os(iOS)
        statusBarHidden()
#else
        self
#endif
    }

    @ViewBuilder
    func alertGlass(interactive: Bool) -> some View {
#if os(visionOS)
        background(.regularMaterial, in: .capsule)
#else
        glassEffect(.regular.interactive(interactive), in: .capsule)
#endif
    }
}

#Preview {
    let alertService = AlertService()
    Text("Cue")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .withAlert()
        .environment(alertService)
        .onAppear {
            alertService.showActionAlert(with: "Downloads Are Full", subtitle: "Tap for Cue Super", imageName: "arrow.down.circle", delay: .seconds(60)) {}
        }
}
