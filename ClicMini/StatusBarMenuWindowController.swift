import AppKit
import SwiftUI
import Foundation
import OSLog

// MARK: Alternative to Menu bar View 
final class StatusBarMenuWindowController: NSWindowController {
    private let log = OSLog(subsystem: String(describing: StatusBarMenuWindowController.self), category: String(describing: StatusBarMenuWindowController.self))

    let statusItem: NSStatusItem?

    var windowWillClose: () -> Void = { }

    init(statusItem: NSStatusItem?, view: some View) {
        self.statusItem = statusItem

//        let height = Double((NSScreen.main?.frame.height ?? 1600.0)/2)

        let hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        let fittingSize = hostingView.fittingSize
        print(fittingSize)
        let windowSize = NSSize(width: 400, height: 800)
        
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.fullSizeContentView, .titled],
            backing: .buffered,
            defer: false,
            screen: statusItem?.button?.window?.screen
        )

        window.isMovable = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.level = .statusBar

        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.level = .floating
        window.animationBehavior = .default

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.material = .hudWindow
        // Masks the behind-window blur too — cornerRadius on its own leaves the
        // backdrop square, which shows as bright corners over a light desktop.
        effect.applyRoundedCornerMask(radius: 24)

        window.contentView = effect
        window.contentView?.addSubview(hostingView)

        window.isOpaque = false
        window.backgroundColor = .clear

        super.init(window: window)

        window.delegate = self
//        setupContentSizeObservation()

//        if let roomMenuBarView = view as? RoomMenuBarView {
//            roomMenuBarView.setSize { height in
//                repositionWindow(height: height)
//            }
//        }
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private var eventMonitor: EventMonitor?

    /// Posting this notification causes the system Menu Bar to stay put when the cursor leaves its area while over a full screen app.
    private func postBeginMenuTrackingNotification() {
        DistributedNotificationCenter.default().post(name: .init("com.apple.HIToolbox.beginMenuTrackingNotification"), object: nil)
    }

    /// Posting this notification reverses the effect of the notification above.
    private func postEndMenuTrackingNotification() {
        DistributedNotificationCenter.default().post(name: .init("com.apple.HIToolbox.endMenuTrackingNotification"), object: nil)
    }

    override func showWindow(_ sender: Any?) {
        postBeginMenuTrackingNotification()

        // Nasty, but necessary so that when our menu window shows up,
        // other windows from Menu Bar items go away.
        NSApp.activate(ignoringOtherApps: true)

        repositionWindow()

        window?.alphaValue = 1

        super.showWindow(sender)

        startMonitoringClicks()
    }

    private func startMonitoringClicks() {
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self = self else { return }
            self.close()
        })
        eventMonitor?.start()
    }

    override func close() {
        postEndMenuTrackingNotification()

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.completionHandler = {
            super.close()

            self.eventMonitor?.stop()
            self.eventMonitor = nil
        }
        window?.animator().alphaValue = 0
        NSAnimationContext.endGrouping()
    }

    // MARK: - Positioning relative to status item

    private struct Metrics {
        static let margin: CGFloat = 0
    }

    func repositionWindow(height: CGFloat? = nil) {
        guard let referenceWindow = statusItem?.button?.window, let window = window else {
            os_log("Couldn't find reference window for repositioning status bar menu window, centering instead", log: self.log, type: .debug)
            self.window?.center()
            return
        }

        let width = window.frame.width
        let height =  height ?? window.frame.height
        var x = referenceWindow.frame.origin.x + referenceWindow.frame.width / 2 - window.frame.width / 2

        if let screen = referenceWindow.screen {
            // If the window extrapolates the limits of the screen, reposition it.
            if (x + width) > (screen.visibleFrame.origin.x + screen.visibleFrame.width) {
                x = (screen.visibleFrame.origin.x + screen.visibleFrame.width) - width - Metrics.margin
            }
        }

        let rect = NSRect(
            x: x,
            y: referenceWindow.frame.origin.y - height - Metrics.margin,
            width: width,
            height: height
        )

        window.setFrame(rect, display: true, animate: false)
    }
}

// MARK: - Window delegate

extension StatusBarMenuWindowController: NSWindowDelegate {

    func windowWillClose(_ notification: Notification) {
        windowWillClose()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        statusItem?.button?.highlight(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        statusItem?.button?.highlight(false)
    }

}

import Cocoa

// Brought to you by: https://www.raywenderlich.com/450-menus-and-popovers-in-menu-bar-apps-for-macos

public class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void

    public init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    deinit {
        stop()
    }

    public func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }

    public func stop() {
        if monitor != nil {
            NSEvent.removeMonitor(monitor!)
            monitor = nil
        }
    }
}
