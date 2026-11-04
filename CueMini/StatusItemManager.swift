import AppKit
import Observation
import ServiceManagement
import SonosKitMini
import SwiftUI

/// Cue Mini's item in the menu bar and the panel it opens: a click shows or
/// hides the player, as the system's Now Playing does, a Command-click or
/// Option-click plays or pauses, and a right click or a Control-click opens
/// Mini's settings as a menu.
///
/// AppKit's rather than SwiftUI's `MenuBarExtra`, whose item on macOS 27 is
/// hosted outside the app: a right click on it never reaches the app, not even
/// an event monitor, and `performClick` set its state without opening its
/// window, so the show/hide shortcut did nothing.
@MainActor
final class StatusItemManager: NSObject, NSWindowDelegate {
    static let shared = StatusItemManager()

    /// The panel's corners, which `MiniMenuScreen` clips its material to: the
    /// panel itself is clear.
    static let panelCornerRadius: CGFloat = 20
    /// Between the menu bar and the panel, and the panel and the screen's edge.
    private static let panelMargin: CGFloat = 6

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var outsideClickMonitor: Any?
    private var shownTitle: MenuBarTitle?

    private override init() {}

    /// Puts the item in the menu bar, once.
    func start() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = .cueMark
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(itemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        followTitle()
    }

    /// Keeps the item's title on what's playing, again whenever that changes.
    private func followTitle() {
        let title = withObservationTracking {
            MenuBarTitle.current
        } onChange: {
            Task { @MainActor in
                StatusItemManager.shared.followTitle()
            }
        }
        guard title != shownTitle else { return }
        shownTitle = title
        statusItem?.button?.attributedTitle = title?.attributed ?? NSAttributedString()
    }

    @objc private func itemClicked() {
        let event = NSApp.currentEvent
        let modifiers = event?.modifierFlags ?? []
        if event?.type == .rightMouseUp || modifiers.contains(.control) {
            closePanel()
            showSettingsMenu()
        } else if !modifiers.isDisjoint(with: [.command, .option]), CueLink.shared.state?.item != nil {
            CueLink.shared.send(.togglePlayback)
        } else {
            togglePanel()
        }
    }

    // MARK: - The panel

    /// Shows or hides the player.
    func togglePanel() {
        if panel == nil {
            openPanel()
        } else {
            closePanel()
        }
    }

    private func openPanel() {
        guard panel == nil, let button = statusItem?.button else { return }
        // Other items' menus give way, and a menu bar that hides itself stays.
        DistributedNotificationCenter.default().post(name: .init("com.apple.HIToolbox.beginMenuTrackingNotification"), object: nil)

        // Sized by what's in it, its top staying under the item.
        let content = MiniMenuScreen()
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                StatusItemManager.shared.fitPanel(to: size)
            }
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        let size = hosting.fittingSize

        let panel = MiniPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.delegate = self
        self.panel = panel

        fitPanel(to: size)
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated {
                // Its own item's click is on its way, and toggles the panel.
                guard !StatusItemManager.shared.isPointerOnItem else { return }
                StatusItemManager.shared.closePanel()
            }
        }
    }

    private func closePanel() {
        guard let panel else { return }
        self.panel = nil
        DistributedNotificationCenter.default().post(name: .init("com.apple.HIToolbox.endMenuTrackingNotification"), object: nil)
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
        panel.delegate = nil
        panel.orderOut(nil)
        // The player goes with it, so it stops scrolling and hears it's gone.
        panel.contentView = nil
        statusItem?.button?.highlight(false)
    }

    /// The screen the item's on. By its middle alone: the item's window reports
    /// a height above the screen, so it may not count as on one.
    private var itemScreen: NSScreen? {
        guard let midX = statusItem?.button?.window?.frame.midX else { return NSScreen.main }
        return NSScreen.screens.first { $0.frame.minX <= midX && midX < $0.frame.maxX } ?? NSScreen.main
    }

    private var isPointerOnItem: Bool {
        guard let item = statusItem?.button?.window?.frame, let screen = itemScreen else { return false }
        let pointer = NSEvent.mouseLocation
        return pointer.x >= item.minX && pointer.x < item.maxX && pointer.y >= screen.visibleFrame.maxY
    }

    /// Under the menu bar, its leading edge at the item's as `MenuBarExtra`
    /// placed it, held on screen.
    private func fitPanel(to size: CGSize) {
        guard let panel, let anchor = statusItem?.button?.window, let screen = itemScreen?.visibleFrame,
              size.width > 0, size.height > 0 else { return }
        let x = min(anchor.frame.minX, screen.maxX - size.width - Self.panelMargin)
        let frame = NSRect(x: x, y: screen.maxY - size.height - Self.panelMargin, width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }

    // MARK: - The settings menu

    private func showSettingsMenu() {
        guard let statusItem else { return }
        statusItem.menu = makeMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func makeMenu() -> NSMenu {
        let settings = MiniSettingsService.shared
        let menu = NSMenu()
        menu.autoenablesItems = false

        let hasPlayer = CueLink.shared.state?.item != nil
        menu.addItem(command(hasPlayer ? "Show in Cue" : "Open Cue", #selector(showCue)))
        menu.addItem(.separator())
        menu.addItem(toggle("Show Song Title in Menu Bar", isOn: settings.showSongTitleInMenuBar, #selector(toggleSongTitle)))
        menu.addItem(toggle("Show Track Change Notifications", isOn: settings.showTrackChangeHUD, #selector(toggleTrackChangeHUD)))
        menu.addItem(toggle("Launch at Login", isOn: SMAppService.mainApp.status == .enabled, #selector(toggleLaunchAtLogin)))
        menu.addItem(.separator())
        menu.addItem(command("Cue Mini Settings…", #selector(openSettings), key: ","))
        menu.addItem(command("Quit Cue Mini", #selector(quit), key: "q"))
        return menu
    }

    private func command(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func toggle(_ title: String, isOn: Bool, _ action: Selector) -> NSMenuItem {
        let item = command(title, action)
        item.state = isOn ? .on : .off
        return item
    }

    @objc private func showCue() {
        if CueLink.shared.state?.item != nil {
            CueLink.shared.showPlayer()
        } else {
            CueLink.shared.openCue()
        }
    }

    @objc private func toggleSongTitle() {
        MiniSettingsService.shared.showSongTitleInMenuBar.toggle()
    }

    @objc private func toggleTrackChangeHUD() {
        MiniSettingsService.shared.showTrackChangeHUD.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        Task {
            await MiniSettingsService.shared.toggleLaunchAtLogin()
        }
    }

    @objc private func openSettings() {
        WindowManager.shared.openPreferences()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

/// A panel that takes the keyboard without Cue Mini coming to the front, for
/// Escape, and so it's told when something else does.
private final class MiniPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        StatusItemManager.shared.togglePanel()
    }
}

/// What the item says beside its mark: the song, dim while it's paused.
@MainActor
private struct MenuBarTitle: Equatable {
    /// The longest title the bar carries, as it's there whenever something's
    /// loaded and a book's chapter can run long.
    private static let limit = 32

    let text: String
    let isPaused: Bool

    /// What Cue's player shows (on this Mac or a speaker), paused or not, else
    /// a playing speaker's song.
    ///
    /// `song`, not `name` — it prefers the stream metadata title and falls back
    /// to `name`, which is what the menu's own rows render.
    static var current: MenuBarTitle? {
        guard MiniSettingsService.shared.showSongTitleInMenuBar else { return nil }
        if let state = CueLink.shared.state, let item = state.item {
            return MenuBarTitle(text: shortened(item.title), isPaused: !state.isPlaying)
        }
        if let song = playingDevice?.track.song {
            return MenuBarTitle(text: shortened(song), isPaused: false)
        }
        return nil
    }

    private static func shortened(_ title: String) -> String {
        title.count > limit ? title.prefix(limit - 1) + "…" : title
    }

    var attributed: NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: isPaused ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ])
    }

    /// A speaker playing, for its song while Cue's player has none.
    ///
    /// `devices` is in discovery order, not the order the menu lists rooms, and
    /// a room can report PLAYING with nothing to show: a soundbar on TV input
    /// has no `dc:title` at all (the codec arrives separately as `tvAudio`), and
    /// an idle or not-yet-resolved room carries `SonosTrack.empty`. Taking the
    /// first playing room blindly lands on one of those and leaves the menu bar
    /// bare while music is playing in another room, so skip the ones with no
    /// title to show.
    private static var playingDevice: SonosDevice? {
        SonosMiniService.shared.devices.first { $0.isPlaying && !$0.isTVMode && !$0.track.song.isEmpty }
    }
}

private extension NSImage {
    /// Cue's play triangle (`CueMark`, shared with the widgets) on the menu
    /// bar's 16-point square, a template the menu bar tints.
    static let cueMark: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let height: CGFloat = 14
            let width = height * CueMark.aspectRatio
            let mark = CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
            context.addPath(CueMark().path(in: mark).cgPath)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
