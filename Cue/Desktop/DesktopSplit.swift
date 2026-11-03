#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// The Mac window's two columns in UIKit's split view: the sidebar in its
/// sidebar column, on macOS's own sidebar material (`primaryBackgroundStyle`
/// `.sidebar`: the desktop shows through it, as through Music's), and
/// `DesktopContent` beside it. A Catalyst app gets that material only in
/// that column; a SwiftUI material blurs the window, not what's behind it.
///
/// Each column is a hosting controller of its own, made once, so its root
/// gives it what the window gives the shell (`DesktopColumn`). The split
/// never collapses or hides the sidebar: the window's width is held above
/// what both need (`CueSceneDelegate`).
struct DesktopSplit: UIViewControllerRepresentable {
    /// At the window's scale (`InterfaceSize`).
    let sidebarWidth: CGFloat
    let zoomNamespace: Namespace.ID?

    func makeUIViewController(context: Context) -> UISplitViewController {
        let sidebar = UIHostingController(rootView: DesktopColumn(zoomNamespace: zoomNamespace) {
            DesktopSidebar()
        })
        // Clear, so the material shows through.
        sidebar.view.backgroundColor = .clear
        let content = UIHostingController(rootView: DesktopColumn(zoomNamespace: zoomNamespace) {
            DesktopContent()
        })
        // Both columns lay out as the window does: the sidebar column reports
        // compact by itself, which turns popovers into sheets.
        for column in [sidebar, content] {
            column.traitOverrides.horizontalSizeClass = .regular
        }

        let split = UISplitViewController(style: .doubleColumn)
        split.setViewController(sidebar, for: .primary)
        split.setViewController(content, for: .secondary)
        // Each column comes in a navigation controller of the split's own,
        // whose bar would sit over the page's.
        for column in [sidebar, content] {
            column.navigationController?.setNavigationBarHidden(true, animated: false)
        }
        split.primaryBackgroundStyle = .sidebar
        split.preferredDisplayMode = .oneBesideSecondary
        split.preferredSplitBehavior = .tile
        split.displayModeButtonVisibility = .never
        split.presentsWithGesture = false
        setWidth(of: split)
        return split
    }

    func updateUIViewController(_ split: UISplitViewController, context: Context) {
        setWidth(of: split)
    }

    /// Fixed, as the sidebar was: neither dragged nor a share of the
    /// window.
    private func setWidth(of split: UISplitViewController) {
        guard split.preferredPrimaryColumnWidth != sidebarWidth else { return }
        split.minimumPrimaryColumnWidth = sidebarWidth
        split.maximumPrimaryColumnWidth = sidebarWidth
        split.preferredPrimaryColumnWidth = sidebarWidth
    }
}

/// A column's root: what the window gives the shell (`CueApp`), which a
/// hosting controller of its own doesn't inherit. The services in the
/// environment, the zoom namespace, the iPad's layout, and the window's
/// scale, read here so a change reaches the column.
private struct DesktopColumn<Content: View>: View {
    let zoomNamespace: Namespace.ID?
    @ViewBuilder let content: () -> Content

    @State private var appState = AppState.shared

    var body: some View {
        content()
            .withEnvironments()
            .environment(\.zoomNamespace, zoomNamespace)
            .environment(\.usesPadLayout, true)
            .interfaceSize(appState.interfaceSize)
    }
}
#endif
