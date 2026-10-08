import OSLog
import SwiftUI
import SonosKit
import VibesDS
import UIKit

/// The app's toast: a glass capsule just under the status bar with the
/// alert's artwork, text and symbol. It opens out from under the navigation
/// bar as it comes in and fades away as it goes, both drawn as a scale and
/// a fade so nothing is laid out again frame by frame. It keeps one width
/// while it's up, and a change to what it says crossfades in place.
///
/// On iOS it's in a window of its own over each scene (`AlertWindow`), so it
/// sits above every sheet, cover and bar. On the Mac and visionOS screens
/// host it (`withAlert()`), and only the one that joined a window last draws
/// it (`AlertService.frontHost`), so a sheet's doesn't show it a second time
/// over the screen behind.
struct AlertView: View {
    /// In the alert's own window (iOS) rather than over a screen.
    var inWindow = false
    /// Where the capsule is, in the window's coordinates, for the alert's
    /// window to take touches there and nowhere else.
    var onCapsuleFrame: ((CGRect) -> Void)? = nil

    @Environment(AlertService.self) private var alertService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var id = UUID()
    /// How far the capsule is being dragged. Up follows the finger and puts
    /// it away; down gives a little, then stops.
    @State private var drag: CGFloat = 0

    private var alert: Alert { alertService.alert }

    var body: some View {
        // Inside the safe area, so the capsule's top is the status bar's
        // foot (or, over a Mac screen, the toolbar's).
        ZStack(alignment: .top) {
            if alert.isShowing, inWindow || alertService.frontHost == id {
                capsule
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Opens with a little spring; fades out without one.
        .animation(alert.isShowing ? .spring(duration: 0.45, bounce: 0.2) : .easeOut(duration: 0.3), value: alert.isShowing)
        // In line while it's in a window, not between onAppear and
        // onDisappear: a sheet closed by a play (Search, an album) as the
        // player came up could stay in line, and the player's host never
        // drew the alert.
        .background(alignment: .topLeading) {
            if !inWindow {
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
        }
#if DEBUG
        .onChange(of: alert.isShowing) { _, isShowing in
            guard isShowing else { return }
            let name = String(id.uuidString.prefix(4))
            let isDrawing = inWindow || alertService.frontHost == id
            Self.log.debug("host \(name, privacy: .public): drawing \(isDrawing), in window \(inWindow)")
        }
#endif
    }

    private static let log = Logger(subsystem: "dance.cue", category: "alert")
}

// MARK: - Capsule

private extension AlertView {
    /// As wide as the screen allows, up to 440 points, whatever it says, so
    /// a change while it's up (the spinner going once the speaker has the
    /// music) doesn't resize it; what does change animates in place.
    var capsule: some View {
        row
            .padding(.leading, alert.content == nil ? 16 : 10)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .alertGlass(interactive: alert.handleTap != nil)
            .contentShape(.capsule)
            .animation(.snappy(duration: 0.3), value: look)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onCapsuleFrame?($0) }
            .modifier(AlertInteraction(alertService: alertService, drag: $drag))
            .frame(maxWidth: 440)
            .transition(entranceAndExit)
            .offset(y: drag < 0 ? drag : pull)
            .padding(.top, 4)
            .padding(.horizontal, 16)
    }

    /// In: opens out from a narrow pill tucked under the navigation bar.
    /// Out: fades. Reduce Motion fades both ways.
    var entranceAndExit: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: OpenOut(isClosed: true), identity: OpenOut(isClosed: false)),
            removal: .opacity
        )
    }

    /// What the capsule shows, for animating a change to it in place.
    var look: Look {
        Look(text: alert.text, subtitle: alert.subtitle, imageName: alert.imageName, isLoading: alert.isLoading, contentID: alert.content?.id)
    }

    /// The artwork, then the text, with the symbol (or the spinner while
    /// something's on its way to a speaker) at the end. Without artwork the
    /// symbol leads, as in the system's own banners.
    var row: some View {
        HStack(spacing: 12) {
            if let content = alert.content {
                VibeContentArtworkView(content: content, showMusicSource: false)
                    .frame(width: 40, height: 40)
            } else if hasAccessory {
                accessory
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(alert.text)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.opacity)
                if alert.subtitle != "" {
                    Text(alert.subtitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .transition(.opacity)
                }
            }
            .lineLimit(2)
            Spacer(minLength: 0)
            if alert.content != nil {
                accessory
            }
        }
        .fontDesign(.rounded)
    }

    var hasAccessory: Bool {
        alert.isLoading || !(alert.imageName ?? "").isEmpty
    }

    /// One slot, the same size whatever's in it (the spinner, a symbol or
    /// nothing), so one taking the other's place crossfades rather than
    /// resizing the row.
    var accessory: some View {
        ZStack {
            if alert.isLoading {
                ProgressView()
                    .tint(.secondary)
                    .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.6)))
            } else if let imageName = alert.imageName, !imageName.isEmpty {
                Image(systemName: imageName)
                    .font(.title3.weight(.semibold))
                    .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .frame(width: 26, height: 26)
    }

    /// A downward drag, damped so it gives about 12 points at most.
    var pull: CGFloat {
        drag > 0 ? 12 * (1 - exp(-drag / 60)) : 0
    }
}

/// What the capsule shows: the alert's text, symbol, spinner and artwork.
private struct Look: Equatable {
    var text: String
    var subtitle: LocalizedStringKey
    var imageName: String?
    var isLoading: Bool
    var contentID: String?
}

/// The entrance: from a narrower, shorter pill under the navigation bar,
/// opening out to full size. A scale rather than a frame, so it's drawn
/// without laying the capsule out again each frame.
private struct OpenOut: ViewModifier {
    let isClosed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: isClosed ? 0.4 : 1, y: isClosed ? 0.6 : 1, anchor: .top)
            .opacity(isClosed ? 0 : 1)
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

// MARK: - Hosts

/// Tells a host when it joins or leaves a window. UIKit always says: a
/// sheet's views leave when it closes, and the screen's under a full-screen
/// cover while it's up.
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

private extension View {
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
        .overlay(alignment: .top) {
            AlertView()
        }
        .environment(alertService)
        .onAppear {
            alertService.showActionAlert(with: "Downloads Are Full", subtitle: "Tap for Cue Super", imageName: "arrow.down.circle", delay: .seconds(60)) {}
        }
}
