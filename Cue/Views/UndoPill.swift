import SwiftUI
import UIKit

/// A small Undo pill at the top of the screen, over everything: the tabs,
/// sheets and the full-screen player alike, which an overlay on one view
/// (`withAlert`) can't reach. It lives in a window of its own above the
/// app's, the pill's own size, centred under the status bar, so it takes
/// touches on the pill and nowhere else. (A wider window passing on the
/// touches off the pill had to find the pill in it, and SwiftUI's frame
/// for it came out 43 points from where it was drawn: every tap missed.)
/// It goes by itself after a few seconds; a tap runs the undo at once.
@MainActor
@Observable
final class UndoPill {
    static let shared = UndoPill()

    struct Offer: Identifiable {
        let id = UUID()
        /// Where Undo goes back to.
        let name: String
        let action: () -> Void
    }

    /// What's offered, nil while nothing is.
    private(set) var offer: Offer?

    @ObservationIgnored private var window: UIWindow?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// Between a navigation bar's buttons on a phone, a long chapter name
    /// cut short in the middle rather than covering them.
    private static let widest: CGFloat = 250

    func show(_ name: String, for duration: Duration = .seconds(5), action: @escaping () -> Void) {
        guard let key = Self.appWindow() else { return }
        withAnimation(.bouncy(duration: 0.35)) {
            offer = Offer(name: name, action: action)
        }
        place(over: key)
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
        AccessibilityNotification.Announcement("Undo available: back to \(name)").post()
    }

    func undo() {
        guard let offer else { return }
        hide()
        offer.action()
    }

    func hide() {
        hideTask?.cancel()
        // No more touches while it fades.
        window?.isUserInteractionEnabled = false
        withAnimation(.smooth(duration: 0.2)) {
            offer = nil
        } completion: { [weak self] in
            guard let self, offer == nil else { return }
            window?.isHidden = true
        }
    }

    /// The window in front of the scene the person is using (on the Mac,
    /// the one in front), which the pill sits over.
    private static func appWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }
            .flatMap(\.windows)
            .filter { $0.rootViewController as? UIHostingController<UndoPillView> == nil }
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    /// Makes the pill's window, or moves it to `key`'s scene, and sizes it
    /// to the pill, centred under the status bar. Its look follows the
    /// app's chosen appearance.
    private func place(over key: UIWindow) {
        guard let scene = key.windowScene else { return }
        if window?.windowScene !== scene {
            window?.isHidden = true
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert - 1
            window.backgroundColor = .clear
            let host = UIHostingController(rootView: UndoPillView(pill: self))
            host.view.backgroundColor = .clear
            host.safeAreaRegions = []
            window.rootViewController = host
            self.window = window
        }
        guard let window, offer != nil else { return }
        let bounds = key.bounds
        // Measured from a label of its own with the name in it: the
        // window's view may still be drawing the pill before (or none),
        // which sized the window to the arrow alone.
        let size = UIHostingController(rootView: UndoPillLabel(name: offer?.name ?? ""))
            .sizeThatFits(in: CGSize(width: min(bounds.width - 32, Self.widest), height: 100))
        window.frame = CGRect(
            x: key.frame.minX + (bounds.width - size.width) / 2,
            y: key.frame.minY + key.safeAreaInsets.top + 6,
            width: size.width,
            height: size.height
        )
        window.overrideUserInterfaceStyle = key.overrideUserInterfaceStyle
        window.isUserInteractionEnabled = true
        window.isHidden = false
    }
}

struct UndoPillView: View {
    let pill: UndoPill

    var body: some View {
        if let offer = pill.offer {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                pill.undo()
            } label: {
                UndoPillLabel(name: offer.name)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo, back to \(offer.name)")
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .id(offer.id)
        }
    }
}

/// The pill itself, glass like the app's other floating controls: Undo,
/// and where it goes back to.
private struct UndoPillLabel: View {
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.uturn.backward")
            Text("Undo")
                .fontWeight(.semibold)
            // Cut in the middle: the chapter's start and the time stay.
            Text(name)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
        .fontDesign(.rounded)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassPill()
        .contentShape(.capsule)
    }
}
