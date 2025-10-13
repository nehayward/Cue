import Cocoa
import SwiftUI

class MediaIndicatorWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: backingStoreType, defer: flag)
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.ignoresMouseEvents = true
        self.hasShadow = false
        self.isMovable = false
        self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
    }
}

@MainActor
final class HudWindowManager {
    static let shared = HudWindowManager()
    
    private var window: NSWindow?
    private var hideTask: Task<Void, Never>?
    private var lastInteractionTime: Date = Date()
    private var currentHostingView: NSHostingView<MediaIndicatorView>?
    
    private init() {}
    
    deinit {
        hideTask?.cancel()
        currentHostingView = nil
        window = nil
    }
    
    func showMediaIndicator(speakerName: String, action: MediaIndicatorView.MediaAction, isPlaying: Bool = true) {
        // Update last interaction time
        lastInteractionTime = Date()
        
        // Cancel any existing hide task
        hideTask?.cancel()
        
        // Get screen dimensions for positioning
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        
        // Create or update window
        if window == nil {
            let windowRect = NSRect(x: 0, y: 0, width: 240, height: 120)
            window = NSWindow(
                contentRect: windowRect,
                styleMask: [.borderless, .hudWindow],
                backing: .buffered,
                defer: false
            )
        }
        
        guard let window = window else { return }
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.animationBehavior = .alertPanel
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.makeKeyAndOrderFront(self)

        // Position window in top-right corner
        let windowSize = NSSize(width: 240, height: 120)
        let margin: CGFloat = 20
        let windowFrame = NSRect(
            x: screenFrame.maxX - windowSize.width - margin,
            y: screenFrame.maxY - windowSize.height - margin,
            width: windowSize.width,
            height: windowSize.height
        )
        
        window.setFrame(windowFrame, display: true)
        
        // Clean up previous hosting view to prevent memory accumulation
        currentHostingView?.removeFromSuperview()
        currentHostingView = nil
        
        // Create the effect view with proper frame
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height))
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.material = .hudWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 24
        
        // Create the SwiftUI view
        let mediaView = MediaIndicatorView(
            speakerName: speakerName,
            action: action
        )
        
        let hostingView = NSHostingView(rootView: mediaView)
        hostingView.frame = effect.bounds
        hostingView.autoresizingMask = [.width, .height]
        
        // Store reference to hosting view for cleanup
        currentHostingView = hostingView
        
        effect.addSubview(hostingView)
        window.contentView = effect
        
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.styleMask.remove(.titled)
        
        // Show window with animation (only if not already visible)
        if window.alphaValue == 0 {
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1.0
            }
        } else {
            // Window is already visible, just update the content
            window.orderFrontRegardless()
        }
        
        // Start auto-hide timer with smart delay
        startAutoHideTimer()
    }
    
    private func startAutoHideTimer() {
        hideTask?.cancel()
        hideTask = nil
        
        hideTask = Task { [weak self] in
            guard let self = self else { return }
            // Wait in shorter intervals to check for new interactions
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    // Task cancelled
                    return
                }
                
                // Check if we've been cancelled
                if Task.isCancelled { return }
                
                // Check if enough time has passed since last interaction
                let timeSinceLastInteraction = Date().timeIntervalSince(await self.lastInteractionTime)
                if timeSinceLastInteraction >= 2 {
                    await self.hideMediaIndicator()
                    return
                }
            }
        }
    }
    
    func extendVisibility() {
        // Update last interaction time to keep window visible longer
        lastInteractionTime = Date()
    }
    
    func hideMediaIndicator() {
        guard let window = window else { return }
        
        // Cancel hide task first
        hideTask?.cancel()
        hideTask = nil
        
        // Use a longer, smoother fade like the system volume HUD
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            window.orderOut(nil)
            // Clean up hosting view after hiding
            self?.currentHostingView?.removeFromSuperview()
            self?.currentHostingView = nil
        }
    }
}
