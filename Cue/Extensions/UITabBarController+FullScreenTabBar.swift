#if canImport(UIKit) && !os(watchOS)
import ObjectiveC
import OSLog
import UIKit

/// Lays the tab bar controller out again when UIKit leaves its tab bar
/// covering the whole screen.
///
/// An iPhone Duo opening moves the app to its inner display, where the tab
/// bar runs down the trailing edge. Partway through, UIKit lays the tab bar
/// out over the whole screen (951 × 669, the display itself) and works out
/// each tab's bottom safe area from it: the screen's full height. Nothing
/// laid the controller out again until the phone was turned, so every tab's
/// page had no room above its bottom inset. A list kept drawing its rows
/// (it runs under its insets) but would scroll 669 pt past its end, and
/// Audiobooks, whose scroll view is laid out from the safe area, sat past
/// its own end, shelves at the top and black under them; a new scroll view
/// or one settled back within its content couldn't help, as the page itself
/// was 0 pt tall. One more layout pass puts the bar back at its edge and
/// the inset back to the mini player's. A tab bar the size of the whole
/// view is never a real layout, so this goes by that, whatever caused it.
@MainActor
enum FullScreenTabBarFix {
    private static var isInstalled = false
    private static let log = Logger(subsystem: "dance.cue", category: "tabs")
    /// Passes made at one size, so a layout that won't come right can't
    /// loop: the controller and its view's size, and how many.
    private static var passes: (controller: ObjectIdentifier, size: CGSize, count: Int)?

    static func install() {
        // The iPhone's tab bar alone, the Duo's included (it reports the
        // phone idiom); an iPad's or the Mac's is laid out another way.
        guard UIDevice.current.userInterfaceIdiom == .phone, !isInstalled else { return }
        isInstalled = true
        let selector = #selector(UIViewController.viewDidLayoutSubviews)
        guard let method = class_getInstanceMethod(UITabBarController.self, selector) else { return }
        typealias DidLayout = @convention(c) (UIViewController, Selector) -> Void
        // The tab bar controller's own, or else `UIViewController`'s,
        // which is then its super's: never replaced for every controller.
        let original = unsafeBitCast(method_getImplementation(method), to: DidLayout.self)
        let checked: @convention(block) (UITabBarController) -> Void = { controller in
            original(controller, selector)
            checkTabBar(of: controller)
        }
        let implementation = imp_implementationWithBlock(checked)
        if !class_addMethod(UITabBarController.self, selector, implementation, method_getTypeEncoding(method)) {
            method_setImplementation(method, implementation)
        }
    }

    private static func coversView(_ controller: UITabBarController) -> Bool {
        let size = controller.view.bounds.size
        return size.width > 0 && size.height > 0 && controller.tabBar.frame.size == size
    }

    /// After the layout that left the bar over the whole view, not within
    /// it.
    private static func checkTabBar(of controller: UITabBarController) {
        guard coversView(controller) else { return }
        Task { @MainActor [weak controller] in
            guard let controller, coversView(controller) else { return }
            let id = ObjectIdentifier(controller)
            let size = controller.view.bounds.size
            var count = 1
            if let passes, passes.controller == id, passes.size == size {
                count = passes.count + 1
            }
            guard count <= 3 else { return }
            passes = (id, size, count)
            log.notice("tab bar over the whole \(Int(size.width), privacy: .public)×\(Int(size.height), privacy: .public) view, laid out again")
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
        }
    }
}
#endif
