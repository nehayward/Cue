#if canImport(UIKit) && !os(watchOS)
import ObjectiveC
import UIKit

/// Passes SwiftUI's tabs on to the tab bar controller only when they're
/// other tabs.
///
/// SwiftUI's `TabView` hands UIKit its tabs again (`setTabs(_:animated:)`)
/// on updates that change none of them: the same `UITab` objects in the same
/// order, any new title or image already set on the objects themselves. On
/// the iPhone, each time, UIKit selects the tab again and takes its page out
/// of the window and back. With an accessibility feature on, iOS asks the
/// app for its focused element as it's typed in and scrolled, SwiftUI
/// answers with such an update, and the phone's log had it several times a
/// second: Search's field lost the keyboard as it was typed in (it leaves
/// the window), and a scroll on Audiobooks stopped dead (so does a scroll
/// view). Tabs that are other objects, or in another order, go through.
@MainActor
enum SameTabsFilter {
    private static var isInstalled = false

    static func install() {
        guard #available(iOS 18.0, visionOS 2.0, *), !isInstalled else { return }
        isInstalled = true
        let selector = #selector(UITabBarController.setTabs(_:animated:))
        guard let method = class_getInstanceMethod(UITabBarController.self, selector) else { return }
        typealias SetTabs = @convention(c) (UITabBarController, Selector, NSArray, Bool) -> Void
        let setTabs = unsafeBitCast(method_getImplementation(method), to: SetTabs.self)
        let filtered: @convention(block) (UITabBarController, NSArray, Bool) -> Void = { controller, tabs, animated in
            let current = controller.tabs
            let unchanged = tabs.count == current.count
                && zip(current, tabs).allSatisfy { tab, new in tab === (new as AnyObject) }
            guard !unchanged else {
                ScrollStopLog.note("same tabs again, not passed on")
                return
            }
            setTabs(controller, selector, tabs, animated)
        }
        method_setImplementation(method, imp_implementationWithBlock(filtered))
    }
}
#endif
