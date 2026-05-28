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

/// Hosting view that takes the first click even when its window isn't key, so a
/// single tap on the HUD dismisses it without first having to focus the window.
final class ClickThroughHostingView: NSHostingView<MediaIndicatorView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: MediaIndicatorView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class HudWindowManager {
    static let shared = HudWindowManager()

    private var window: NSWindow?
    private var hideTask: Task<Void, Never>?
    private var lastInteractionTime: Date = Date()
    private var currentHostingView: ClickThroughHostingView?

    /// How long the indicator stays up after the last interaction.
    private var displayDuration: TimeInterval = 2
    /// Drives the alpha fade in/out manually. Stepping alphaValue ourselves is
    /// deterministic — unlike NSAnimationContext's window-alpha animation, which
    /// intermittently failed to animate when kicked off from the async auto-hide
    /// task, making the window snap off instead of fade. A new fade cancels the
    /// previous one, which also handles a show interrupting an in-flight fade-out.
    private var fadeTask: Task<Void, Never>?

    private init() {}

    @MainActor
    deinit {
        hideTask?.cancel()
        hideTask = nil
        fadeTask?.cancel()
        fadeTask = nil
        currentHostingView?.removeFromSuperview()
        currentHostingView = nil
        window?.close()
        window = nil
    }

    /// Manually ramps the window's alpha to `target`, then runs `completion`.
    /// Cancels any in-flight fade first, so an interrupting fade wins cleanly and
    /// a superseded fade's completion never runs.
    private func fadeWindow(to target: CGFloat, duration: TimeInterval, then completion: (() -> Void)? = nil) {
        fadeTask?.cancel()
        guard let window else { return }
        let start = window.alphaValue
        if abs(start - target) < 0.001 {
            window.alphaValue = target
            completion?()
            return
        }
        let steps = max(1, Int((duration * 60).rounded()))
        fadeTask = Task { @MainActor in
            for i in 1...steps {
                if Task.isCancelled { return }
                let t = CGFloat(i) / CGFloat(steps)
                let eased = t * t * (3 - 2 * t) // smoothstep
                window.alphaValue = start + (target - start) * eased
                try? await Task.sleep(for: .milliseconds(16))
            }
            if Task.isCancelled { return }
            window.alphaValue = target
            completion?()
        }
    }
    
    func showMediaIndicator(speakerName: String, action: MediaIndicatorView.MediaAction, isPlaying: Bool = true, displayDuration: TimeInterval = 2) {
        // Update last interaction time
        lastInteractionTime = Date()
        self.displayDuration = displayDuration

        // Cancel the auto-hide poll; the fade-in below cancels any in-flight
        // fade-out so an interrupting show wins cleanly.
        hideTask?.cancel()

        // Get screen dimensions for positioning
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        
        // Wider and shorter than before — a compact media-notification shape.
        let windowSize = NSSize(width: 320, height: 88)

        // Create or update window
        if window == nil {
            let windowRect = NSRect(origin: .zero, size: windowSize)
            window = NSWindow(
                contentRect: windowRect,
                styleMask: [.borderless, .hudWindow],
                backing: .buffered,
                defer: false
            )
            // Start hidden so the very first appearance fades in too.
            window?.alphaValue = 0
        }

        guard let window = window else { return }
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        // .none: we drive show/hide entirely via alphaValue. With .alertPanel the
        // system ran its own order-in/out animation that fought our fade, so the
        // window snapped away instead of fading.
        window.animationBehavior = .none
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // Position window in top-right corner
        let margin: CGFloat = 20
        let windowFrame = NSRect(
            x: screenFrame.maxX - windowSize.width - margin,
            y: screenFrame.maxY - windowSize.height - margin,
            width: windowSize.width,
            height: windowSize.height
        )
        
        window.setFrame(windowFrame, display: true)

        let mediaView = MediaIndicatorView(
            speakerName: speakerName,
            action: action,
            onDismiss: { [weak self] in self?.hideMediaIndicator() }
        )

        if let hostingView = currentHostingView, window.contentView != nil {
            // Already on screen — just swap the SwiftUI content. Rebuilding the
            // effect + hosting view on every 100ms volume tick caused flicker.
            hostingView.rootView = mediaView
        } else {
            // Create the effect view with proper frame
            let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: windowSize))
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.material = .hudWindow
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 18
            effect.layer?.masksToBounds = true
            // Subtle hairline border to lift it off the desktop.
            effect.layer?.borderWidth = 1
            effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

            let hostingView = ClickThroughHostingView(rootView: mediaView)
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
        }
        
        // Order front and fade up to full opacity. Ramping from the current alpha
        // means a show interrupting an in-flight fade-out resumes smoothly.
        window.orderFrontRegardless()
        // Recompute the drop shadow against the rounded content shape.
        window.invalidateShadow()
        fadeWindow(to: 1, duration: 0.25)

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
                if timeSinceLastInteraction >= self.displayDuration {
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
        guard let window else { return }

        // Cancel the auto-hide poll.
        hideTask?.cancel()
        hideTask = nil

        // Fade to transparent, then order out. If a show interrupts the fade,
        // fadeWindow cancels this task so orderOut never runs. The window + hosting
        // view stay alive for reuse (no teardown to snap content out from under us).
        fadeWindow(to: 0, duration: 0.4) {
            window.orderOut(nil)
        }
    }
}
