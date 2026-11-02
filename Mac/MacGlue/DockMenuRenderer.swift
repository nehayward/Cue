import AppKit
import ObjectiveC.runtime

/// Owns the dock menu: cached state, NSMenu rendering, action selectors, and
/// the swizzle that injects `applicationDockMenu(_:)` into the Catalyst
/// NSApplicationDelegate.
///
/// Lives entirely inside the MacGlue bundle so the app side only sees the
/// `DockMenuRenderable` protocol.
///
/// Top to bottom: where Cue plays (This Mac and each Sonos group), Sleep
/// Timer, Playback, Volume (a group only), Now Playing, then the transport.
/// The system adds Options, Show All Windows, Hide and Quit after it.
final class DockMenuRenderer: NSObject, DockMenuRenderable, @unchecked Sendable {

    /// Sleep-timer presets offered in the submenu, in minutes.
    private let sleepTimerPresets = [15, 30, 45, 60]

    // MARK: - Handlers

    private var dockCommandHandler: ((DockCommand) -> Void)?
    private var switchRouteHandler: ((String) -> Void)?
    private var sleepTimerHandler: ((Int) -> Void)?
    private var menuWillOpenHandler: (() -> Void)?

    // MARK: - State

    private var state = DockMenuState()
    private let decoder = JSONDecoder()

    // MARK: - Swizzle anchor

    /// Reachable from the C block we inject into the delegate's class.
    static var shared: DockMenuRenderer?

    // MARK: - DockMenu

    func setupDockMenu() {
        Self.shared = self
        guard let delegate = NSApplication.shared.delegate,
              let delegateClass = object_getClass(delegate) else { return }

        let selector = #selector(NSApplicationDelegate.applicationDockMenu(_:))
        let block: @convention(block) (AnyObject, NSApplication) -> NSMenu? = { _, _ in
            DockMenuRenderer.shared?.buildDockMenu()
        }
        let imp = imp_implementationWithBlock(block as Any)
        // Type encoding `@@:@` = returns object, self is object, _cmd is SEL,
        // first arg is object (NSApplication). `class_replaceMethod` installs
        // our implementation whether or not one already exists: it adds the
        // method if absent, or swaps the existing IMP if present. That keeps
        // this correct regardless of any default `applicationDockMenu`
        // Catalyst may provide — `class_addMethod` would silently no-op when
        // the method is already there.
        class_replaceMethod(delegateClass, selector, imp, "@@:@")
    }

    /// Caches menu state. The dock menu is built synchronously and freshly on
    /// every open (`buildDockMenu`), so this just stores — there's no live
    /// menu to mutate (the Dock snapshots the menu when `applicationDockMenu`
    /// returns and ignores later changes).
    func updateDockMenu(_ state: Data) {
        guard let decoded = try? decoder.decode(DockMenuState.self, from: state) else { return }
        self.state = decoded
    }

    func setDockCommandHandler(_ handler: @escaping (DockCommand) -> Void) {
        dockCommandHandler = handler
    }

    func setSwitchRouteHandler(_ handler: @escaping (String) -> Void) {
        switchRouteHandler = handler
    }

    func setSleepTimerHandler(_ handler: @escaping (Int) -> Void) {
        sleepTimerHandler = handler
    }

    func setMenuWillOpenHandler(_ handler: @escaping () -> Void) {
        menuWillOpenHandler = handler
    }

    // MARK: - Menu construction

    /// Called by the swizzled `applicationDockMenu(_:)` each time the user
    /// opens the dock menu. Fires `menuWillOpenHandler` (a non-blocking nudge
    /// to refresh the cache for next time), then renders from the cache.
    private func buildDockMenu() -> NSMenu {
        menuWillOpenHandler?()
        let menu = NSMenu()
        // Each item's `isEnabled` as set: left to AppKit, an item whose
        // target answers its action is enabled whatever it says.
        menu.autoenablesItems = false
        populate(menu)
        return menu
    }

    /// Fills `menu` from the current `state`, a section at a time with a
    /// separator between each that has something in it.
    private func populate(_ menu: NSMenu) {
        let sections: [[NSMenuItem]] = [
            routeItems(),
            [sleepTimerItem()],
            playbackItems(),
            volumeItems(),
            nowPlayingItems(),
            transportItems(),
        ]
        for section in sections where !section.isEmpty {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            for item in section {
                menu.addItem(item)
            }
        }
        // NB: Catalyst auto-appends "Options" / "Show All Windows" / "Hide" /
        // "Quit". Don't add them ourselves — that's where duplicate-block
        // bugs come from.
    }

    /// This Mac and each Sonos group, the one playback goes to checked. A
    /// group the free tier can't play on carries a lock, and opens the
    /// paywall.
    private func routeItems() -> [NSMenuItem] {
        state.routes.map { route in
            let item = NSMenuItem(title: route.name, action: #selector(switchRouteFromDock(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = route.id
            item.state = route.isCurrent ? .on : .off
            if route.isLocked {
                item.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Cue Super")
            }
            return item
        }
    }

    private func sleepTimerItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Sleep Timer", action: nil, keyEquivalent: "")
        item.submenu = makeSleepTimerSubmenu()
        item.isEnabled = state.canSetSleepTimer
        return item
    }

    /// Repeat and Shuffle while something plays from a queue (not a book),
    /// and Crossfade on a speaker.
    private func playbackItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if let mode = state.repeatMode {
            let title = switch mode {
            case .off: "Repeat Off"
            case .all: "Repeat All"
            case .one: "Repeat One"
            }
            items.append(toggleItem(title: title, isOn: mode != .off, command: .cycleRepeat, enabled: state.canChangePlayMode))
        }
        if let isShuffled = state.isShuffled {
            items.append(toggleItem(title: "Shuffle", isOn: isShuffled, command: .toggleShuffle, enabled: state.canShuffle))
        }
        if let isCrossfaded = state.isCrossfaded {
            items.append(toggleItem(title: "Crossfade", isOn: isCrossfaded, command: .toggleCrossfade, enabled: true))
        }
        guard !items.isEmpty else { return [] }
        return [disabledLabel("Playback")] + items
    }

    /// The group's volume and mutes. Nothing on this Mac, whose volume is
    /// macOS's. (A slider would be nicer, but dock menus don't render custom
    /// `NSMenuItem` views — only standard items, so the level is a disabled
    /// header above ± actions.)
    private func volumeItems() -> [NSMenuItem] {
        guard let volume = state.volume else { return [] }
        let canChange = !state.isVolumeFixed
        var items = [
            disabledLabel(state.isVolumeFixed ? "Volume — Fixed" : "Volume — \(volume)%"),
            actionItem(title: "Volume Up", command: .volumeUp, enabled: canChange),
            alternateItem(title: "Volume Up (+5)", command: .volumeUpLarge, enabled: canChange),
            actionItem(title: "Volume Down", command: .volumeDown, enabled: canChange),
            alternateItem(title: "Volume Down (−5)", command: .volumeDownLarge, enabled: canChange),
            toggleItem(title: "Mute", isOn: state.isMuted, command: .toggleMute, enabled: true),
        ]
        if state.showsMuteAll {
            items.append(actionItem(title: "Mute All Speakers", command: .muteAll, enabled: true))
            items.append(actionItem(title: "Unmute All Speakers", command: .unmuteAll, enabled: true))
        }
        return items
    }

    /// The song (or the book and its chapter), which opens the player, and
    /// Favorite where its service can like it.
    private func nowPlayingItems() -> [NSMenuItem] {
        var items = [disabledLabel("Now Playing")]

        let line = state.nowPlaying.map(truncated) ?? "Not Playing"
        let trackItem = actionItem(title: line, command: .openPlayer, enabled: state.nowPlaying != nil)
        trackItem.indentationLevel = 1
        items.append(trackItem)

        if let note = state.nowPlayingNote {
            let noteItem = disabledLabel(note)
            noteItem.indentationLevel = 1
            items.append(noteItem)
        }

        if state.showsFavorite {
            items.append(toggleItem(title: "Favorite", isOn: state.isFavorite, command: .toggleFavorite, enabled: true))
        }
        return items
    }

    /// Play or Pause, then Next and Previous (a book's ±30/15 s), as Music's
    /// own dock menu orders them.
    private func transportItems() -> [NSMenuItem] {
        var items = [actionItem(title: state.isPlaying ? "Pause" : "Play", command: .playPause, enabled: state.canPlay)]
        if let next = state.nextTitle {
            items.append(actionItem(title: next, command: .next, enabled: state.hasNext))
        }
        if let previous = state.previousTitle {
            items.append(actionItem(title: previous, command: .previous, enabled: state.canGoBack))
        }
        return items
    }

    private func makeSleepTimerSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let enabled = state.canSetSleepTimer
        let endsAt = state.sleepEndsAt.flatMap { $0 > .now ? $0 : nil }
        let active = endsAt != nil || state.sleepsAtEndOfItem

        if state.sleepsAtEndOfItem {
            submenu.addItem(disabledLabel("Sleeps at \(state.endOfItemTitle)"))
            submenu.addItem(.separator())
        } else if let endsAt {
            submenu.addItem(disabledLabel("Sleeps in \(Self.timeLeft(until: endsAt))"))
            submenu.addItem(.separator())
        }

        let off = NSMenuItem(title: "Off", action: #selector(sleepTimerSelected(_:)), keyEquivalent: "")
        off.target = self
        off.representedObject = 0
        off.state = active ? .off : .on
        off.isEnabled = enabled
        submenu.addItem(off)

        submenu.addItem(.separator())

        // The song's or the chapter's end: the command works out how long
        // that is when it's chosen.
        let endOfItem = toggleItem(
            title: state.endOfItemTitle,
            isOn: state.sleepsAtEndOfItem,
            command: .sleepAtEndOfItem,
            enabled: enabled && state.canSleepAtEndOfItem
        )
        submenu.addItem(endOfItem)

        for minutes in sleepTimerPresets {
            let title = minutes % 60 == 0 ? "\(minutes / 60) Hour" : "\(minutes) Minutes"
            let item = NSMenuItem(title: title, action: #selector(sleepTimerSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = minutes
            item.isEnabled = enabled
            submenu.addItem(item)
        }
        return submenu
    }

    /// "23 min", "1 hr 5 min", or "less than a minute", counted as the menu
    /// opens.
    private static func timeLeft(until date: Date) -> String {
        let minutes = Int((date.timeIntervalSinceNow / 60).rounded(.up))
        guard minutes > 0 else { return "less than a minute" }
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) hr"
        default: return "\(hours) hr \(rest) min"
        }
    }

    /// A dock menu is as wide as its longest item, and a long title with a
    /// long artist made it a band across the screen.
    private func truncated(_ line: String) -> String {
        let limit = 60
        guard line.count > limit else { return line }
        return String(line.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// A non-interactive section header / info row.
    private func disabledLabel(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// A plain action item. The `DockCommand` rides on the item's `tag` so a
    /// single selector (`performCommand`) handles every command — adding a new
    /// command needs no new `@objc` method.
    private func actionItem(title: String, command: DockCommand, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performCommand(_:)), keyEquivalent: "")
        item.target = self
        item.tag = command.rawValue
        item.isEnabled = enabled
        return item
    }

    /// Like `actionItem`, but shown only when the user holds Option.
    private func alternateItem(title: String, command: DockCommand, enabled: Bool) -> NSMenuItem {
        let item = actionItem(title: title, command: command, enabled: enabled)
        item.isAlternate = true
        item.keyEquivalentModifierMask = .option
        return item
    }

    /// Like `actionItem`, with a checkmark reflecting `isOn`.
    private func toggleItem(title: String, isOn: Bool, command: DockCommand, enabled: Bool) -> NSMenuItem {
        let item = actionItem(title: title, command: command, enabled: enabled)
        item.state = isOn ? .on : .off
        return item
    }

    // MARK: - Actions

    /// Single entry point for every `DockCommand` menu item — the command is
    /// read back from the item's `tag`.
    @objc private func performCommand(_ sender: NSMenuItem) {
        guard let command = DockCommand(rawValue: sender.tag) else { return }
        // Opening the player deliberately brings Cue forward; transport and
        // toggle commands deliberately don't — controlling playback from the
        // dock shouldn't yank Cue (and its menu bar) into the foreground.
        if command == .openPlayer {
            NSApp.activate()
        }
        dockCommandHandler?(command)
    }

    @objc private func switchRouteFromDock(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let index = state.routes.firstIndex(where: { $0.id == id }) else { return }
        if state.routes[index].isLocked {
            // The paywall goes up in Cue's window, so Cue comes forward.
            NSApp.activate()
        } else {
            // Shows the new choice on the next open even before the app's
            // state comes back round.
            for i in state.routes.indices {
                state.routes[i].isCurrent = i == index
            }
        }
        switchRouteHandler?(id)
    }

    @objc private func sleepTimerSelected(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        sleepTimerHandler?(minutes)
    }
}
