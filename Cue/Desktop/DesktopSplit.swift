#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// The Mac window's columns in UIKit's split view: the sidebar in its
/// sidebar column, on macOS's own sidebar material (`primaryBackgroundStyle`
/// `.sidebar`: the desktop shows through it, as through Music's),
/// `DesktopContent` beside it, and the queue in its inspector column, which
/// takes the same material. A Catalyst app gets that material only in a
/// split view's side columns; a SwiftUI material blurs the window, not
/// what's behind it.
///
/// Each column is a hosting controller of its own, made once, so its root
/// gives it what the window gives the shell (`DesktopColumn`). The split
/// never collapses or hides the sidebar: the window's width is held above
/// what both need (`CueSceneDelegate`).
struct DesktopSplit: UIViewControllerRepresentable {
    /// At the window's scale (`InterfaceSize`).
    let sidebarWidth: CGFloat
    let queueWidth: CGFloat
    /// The queue, in the inspector column, on the same material.
    let showsQueue: Bool
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
        let queue = UIHostingController(rootView: DesktopColumn(zoomNamespace: zoomNamespace) {
            DesktopQueuePanel()
        })
        queue.view.backgroundColor = .clear
        let columns = [sidebar, content, queue]
        // Every column lays out as the window does: the side columns report
        // compact by themselves, which turns popovers into sheets.
        for column in columns {
            column.traitOverrides.horizontalSizeClass = .regular
        }

        let split = UISplitViewController(style: .doubleColumn)
        split.setViewController(sidebar, for: .primary)
        split.setViewController(content, for: .secondary)
        split.setViewController(queue, for: .inspector)
        // Each column comes in a navigation controller of the split's own,
        // whose bar would sit over the page's.
        for column in columns {
            column.navigationController?.setNavigationBarHidden(true, animated: false)
        }
        split.primaryBackgroundStyle = .sidebar
        split.preferredDisplayMode = .oneBesideSecondary
        split.preferredSplitBehavior = .tile
        split.displayModeButtonVisibility = .never
        split.presentsWithGesture = false
        setWidths(of: split)
        if showsQueue {
            split.show(.inspector)
        }
        return split
    }

    func updateUIViewController(_ split: UISplitViewController, context: Context) {
        setWidths(of: split)
        // Shown and hidden by the split, in SwiftUI's animation: left to
        // UIKit's own, the column slid but the page beside it, the bar
        // with it, jumped to its new width at once.
        if showsQueue != split.isShowing(.inspector) {
            context.animate {
                if showsQueue {
                    split.show(.inspector)
                } else {
                    split.hide(.inspector)
                }
                split.view.layoutIfNeeded()
            }
        }
    }

    /// Fixed, as the panels were: neither dragged nor a share of the
    /// window.
    private func setWidths(of split: UISplitViewController) {
        if split.preferredPrimaryColumnWidth != sidebarWidth {
            split.minimumPrimaryColumnWidth = sidebarWidth
            split.maximumPrimaryColumnWidth = sidebarWidth
            split.preferredPrimaryColumnWidth = sidebarWidth
        }
        if split.preferredInspectorColumnWidth != queueWidth {
            split.minimumInspectorColumnWidth = queueWidth
            split.maximumInspectorColumnWidth = queueWidth
            split.preferredInspectorColumnWidth = queueWidth
        }
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
