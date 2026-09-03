import AppKit
import ObjectiveC.runtime

/// Owns the dock menu: cached state, NSMenu rendering, action selectors, and
/// the swizzle that injects `applicationDockMenu(_:)` into the Catalyst
/// NSApplicationDelegate.
///
/// Lives entirely inside the MacGlue bundle so the app side only sees the
/// `DockMenuRenderable` protocol.
final class DockMenuRenderer: NSObject, DockMenuRenderable, @unchecked Sendable {

    /// Everything the menu renders from. Refreshed via `updateDockMenu`; read
    /// by `populate` each time the dock menu is built.
    private struct State {
        var speakerName: String?
        var trackTitle: String?
        var trackArtist: String?
        var isPlaying = false
        var isRepeatAll = false
        var isShuffle = false
        var isCrossfade = false
        var isMuted = false
        var volume = 0
        var favoriteSupported = false
        var sleepMinutesRemaining = 0
        var groupIDs: [String] = []
        var groupNames: [String] = []
        var selectedGroupID: String?
    }

    /// Sleep-timer presets offered in the submenu, in minutes.
    private let sleepTimerPresets = [15, 30, 45, 60]

    // MARK: - Handlers

    private var dockCommandHandler: ((DockCommand) -> Void)?
    private var switchGroupHandler: ((String) -> Void)?
    private var sleepTimerHandler: ((Int) -> Void)?
    private var menuWillOpenHandler: (() -> Void)?

    // MARK: - State

    private var state = State()

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
    func updateDockMenu(
        speakerName: String?,
        trackTitle: String?,
        trackArtist: String?,
        isPlaying: Bool,
        isRepeatAll: Bool,
        isShuffle: Bool,
        isCrossfade: Bool,
        isMuted: Bool,
        volume: Int,
        favoriteSupported: Bool,
        sleepMinutesRemaining: Int,
        groupIDs: [String],
        groupNames: [String],
        selectedGroupID: String?
    ) {
        state = State(
            speakerName: speakerName,
            trackTitle: trackTitle,
            trackArtist: trackArtist,
            isPlaying: isPlaying,
            isRepeatAll: isRepeatAll,
            isShuffle: isShuffle,
            isCrossfade: isCrossfade,
            isMuted: isMuted,
            volume: volume,
            favoriteSupported: favoriteSupported,
            sleepMinutesRemaining: sleepMinutesRemaining,
            groupIDs: groupIDs,
            groupNames: groupNames,
            selectedGroupID: selectedGroupID
        )
    }

    func setDockCommandHandler(_ handler: @escaping (DockCommand) -> Void) {
        dockCommandHandler = handler
    }

    func setSwitchGroupHandler(_ handler: @escaping (String) -> Void) {
        switchGroupHandler = handler
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
        populate(menu)
        return menu
    }

    /// Fills `menu` from the current `state`.
    private func populate(_ menu: NSMenu) {
        let hasSpeaker = state.speakerName != nil

        // Sleep Timer submenu
        let sleepItem = NSMenuItem(title: "Sleep Timer", action: nil, keyEquivalent: "")
        sleepItem.submenu = makeSleepTimerSubmenu(enabled: hasSpeaker)
        sleepItem.isEnabled = hasSpeaker
        menu.addItem(sleepItem)

        menu.addItem(.separator())

        // Playback modes
        menu.addItem(disabledLabel("Playback"))
        menu.addItem(toggleItem(title: "Repeat", isOn: state.isRepeatAll, command: .toggleRepeat, enabled: hasSpeaker))
        menu.addItem(toggleItem(title: "Shuffle", isOn: state.isShuffle, command: .toggleShuffle, enabled: hasSpeaker))
        menu.addItem(toggleItem(title: "Crossfade", isOn: state.isCrossfade, command: .toggleCrossfade, enabled: hasSpeaker))

        menu.addItem(.separator())

        // Volume + mute. (A slider would be nicer, but dock menus don't
        // render custom `NSMenuItem` views — only standard items, so we show
        // the level as a disabled header above ± actions.)
        if hasSpeaker {
            menu.addItem(disabledLabel("Volume — \(state.volume)%"))
        }
        menu.addItem(actionItem(title: "Volume Up", command: .volumeUp, enabled: hasSpeaker))
        menu.addItem(alternateItem(title: "Volume Up (+5)", command: .volumeUpLarge, enabled: hasSpeaker))
        menu.addItem(actionItem(title: "Volume Down", command: .volumeDown, enabled: hasSpeaker))
        menu.addItem(alternateItem(title: "Volume Down (−5)", command: .volumeDownLarge, enabled: hasSpeaker))
        menu.addItem(toggleItem(title: "Mute", isOn: state.isMuted, command: .toggleMute, enabled: hasSpeaker))
        let hasAnySpeaker = !state.groupIDs.isEmpty
        menu.addItem(actionItem(title: "Mute All Speakers", command: .muteAll, enabled: hasAnySpeaker))
        menu.addItem(actionItem(title: "Unmute All Speakers", command: .unmuteAll, enabled: hasAnySpeaker))

        menu.addItem(.separator())

        // Room name doubles as the "Switch Speaker" submenu trigger.
        let roomHeader = NSMenuItem(title: state.speakerName ?? "No Speaker Selected", action: nil, keyEquivalent: "")
        roomHeader.submenu = makeGroupsSubmenu()
        roomHeader.isEnabled = !state.groupIDs.isEmpty
        menu.addItem(roomHeader)

        menu.addItem(.separator())

        // Now Playing: disabled label, track line, and Favorite grouped together.
        menu.addItem(disabledLabel("Now Playing"))

        let trackItem = actionItem(title: nowPlayingLine(), command: .openSpeaker, enabled: hasSpeaker)
        trackItem.indentationLevel = 1
        menu.addItem(trackItem)

        // Favorite — the toggle command resolves the current state itself,
        // so the item label stays a plain verb.
        menu.addItem(actionItem(title: "Favorite", command: .toggleFavorite, enabled: hasSpeaker && state.favoriteSupported))

        menu.addItem(.separator())

        // Transport
        menu.addItem(actionItem(title: state.isPlaying ? "Pause" : "Play", command: .playPause, enabled: hasSpeaker))
        menu.addItem(actionItem(title: "Next", command: .next, enabled: hasSpeaker))
        menu.addItem(actionItem(title: "Previous", command: .previous, enabled: hasSpeaker))

        // NB: Catalyst auto-appends "Options" / "Show All Windows" / "Hide" /
        // "Quit". Don't add them ourselves — that's where duplicate-block
        // bugs come from.
    }

    private func makeSleepTimerSubmenu(enabled: Bool) -> NSMenu {
        let submenu = NSMenu()
        let active = state.sleepMinutesRemaining > 0

        if active {
            submenu.addItem(disabledLabel("Sleeps in \(state.sleepMinutesRemaining) min"))
            submenu.addItem(.separator())
        }

        let off = NSMenuItem(title: "Off", action: #selector(sleepTimerSelected(_:)), keyEquivalent: "")
        off.target = self
        off.representedObject = 0
        off.state = active ? .off : .on
        off.isEnabled = enabled
        submenu.addItem(off)

        submenu.addItem(.separator())

        for minutes in sleepTimerPresets {
            let title = minutes % 60 == 0 ? "\(minutes / 60) Hour" : "\(minutes) Minutes"
            let item = NSMenuItem(title: title, action: #selector(sleepTimerSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = minutes
            item.isEnabled = enabled
            submenu.addItem(item)
        }

        // "End of Song" sets a timer for the current track's remaining time.
        // Only meaningful while something is playing — the command resolves the
        // exact duration itself, so it routes through the regular command path.
        submenu.addItem(.separator())
        submenu.addItem(actionItem(title: "End of Song", command: .sleepAtEndOfTrack, enabled: enabled && state.isPlaying))
        return submenu
    }

    private func makeGroupsSubmenu() -> NSMenu {
        let submenu = NSMenu()

        // Disabled title at the top of the submenu so the chevron's intent is
        // obvious when the parent item is just a room name.
        submenu.addItem(disabledLabel("Switch Speaker"))
        submenu.addItem(.separator())

        for (id, name) in zip(state.groupIDs, state.groupNames) {
            let item = NSMenuItem(title: name, action: #selector(switchGroupFromDock(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = (id == state.selectedGroupID) ? .on : .off
            submenu.addItem(item)
        }
        if state.groupIDs.isEmpty {
            submenu.addItem(disabledLabel("No Speakers Available"))
        }
        return submenu
    }

    private func nowPlayingLine() -> String {
        let title = state.trackTitle?.trimmingCharacters(in: .whitespaces) ?? ""
        let artist = state.trackArtist?.trimmingCharacters(in: .whitespaces) ?? ""
        switch (title.isEmpty, artist.isEmpty) {
        case (true, true): return "Nothing Playing"
        case (false, true): return title
        case (true, false): return artist
        case (false, false): return "\(title) — \(artist)"
        }
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
        // "Open Speaker" deliberately brings the app forward; transport and
        // toggle commands deliberately don't — controlling playback from the
        // dock shouldn't yank Cue (and its menu bar) into the foreground.
        if command == .openSpeaker {
            NSApp.activate(ignoringOtherApps: true)
        }
        dockCommandHandler?(command)
    }

    @objc private func switchGroupFromDock(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        // Optimistically reflect the new selection so the next menu open is
        // correct immediately, even before the async refresh round-trip lands.
        if let index = state.groupIDs.firstIndex(of: id) {
            state.selectedGroupID = id
            state.speakerName = state.groupNames[index]
        }
        switchGroupHandler?(id)
    }

    @objc private func sleepTimerSelected(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        sleepTimerHandler?(minutes)
    }
}
