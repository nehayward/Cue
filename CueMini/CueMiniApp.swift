import SwiftUI
import SonosKitMini
import KeyboardShortcuts
import Nuke

@MainActor
@Observable
final class MenuVisibilityService {
    static let shared = MenuVisibilityService()
    private(set) var isMenuVisible = false
    private init() {}
    
    func setMenuVisible(_ visible: Bool) {
        isMenuVisible = visible
    }
}

@main
struct CueMiniApp: App {
    // Don't store singletons as properties - access directly via .shared
    // This prevents unnecessary strong references and memory retention

    /// Notification name for show menu requests from main Cue app
    static let showMenuNotification = Notification.Name("com.cue.mini.showMenu")

    /// Guards the app-lifetime registrations below. If SwiftUI ever re-creates
    /// the App struct, running them again would stack duplicate notification
    /// observers, keyboard-shortcut handlers, and callbacks — each a small leak
    /// and a source of double-fired actions.
    @MainActor private static var didRegisterGlobalHandlers = false

    init() {
        // Initialize global services to ensure they're set up
        _ = CueLink.shared
        _ = GlobalMediaControlService.shared
        _ = SonosMiniService.shared
        _ = MiniSettingsService.shared

        guard !Self.didRegisterGlobalHandlers else { return }
        Self.didRegisterGlobalHandlers = true

        KeyboardShortcuts.onKeyUp(for: .toggleCueMini) {
            Self.clickStatusItem()
        }

        // Listen for show menu requests from main Cue app
        DistributedNotificationCenter.default().addObserver(
            forName: Self.showMenuNotification,
            object: nil,
            queue: .main
        ) { _ in
            Self.clickStatusItem()
        }

        // Check for --show-menu launch argument
        if CommandLine.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Self.clickStatusItem()
            }
        }
        
        // The HUD for a new song in Cue's player on this Mac. A speaker's
        // has the speaker's own, below.
        CueLink.shared.onTrackChanged = { state in
            guard let item = state.item,
                  MiniSettingsService.shared.showTrackChangeHUD,
                  !MenuVisibilityService.shared.isMenuVisible else { return }
            HudWindowManager.shared.extendVisibility()
            HudWindowManager.shared.showMediaIndicator(
                speakerName: state.route.name,
                action: .track(direction: nil, title: item.title, artist: item.subtitle,
                               albumName: item.artworkKey ?? "", imageURL: CueLink.shared.coverURL, loading: false),
                isPlaying: true,
                displayDuration: 5
            )
        }

        // Set up track change callback to show HUD
        // Access service directly and use unowned to avoid retain cycles
        SonosMiniService.shared.onTrackChanged = { group, track in
            Task { @MainActor in
                if MiniSettingsService.shared.showTrackChangeHUD && !MenuVisibilityService.shared.isMenuVisible {
                    HudWindowManager.shared.extendVisibility()
                    
                    // Show track change indicator
                    HudWindowManager.shared.showMediaIndicator(
                        speakerName: group.nameWithCount,
                        action: .track(direction: nil, title: track.name, artist: track.artist,
                                       albumName: track.album, imageURL: track.sonosAlbumArtURL, loading: false),
                        isPlaying: true,
                        displayDuration: 5
                    )
                }
            }
        }
        
//        #if DEBUG
//        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//            let statusItem = NSApp.windows.first?.value(forKey: "statusItem") as? NSStatusItem
//            statusItem?.button?.performClick(nil)
//        }
//        #endif
        
        // Configure Nuke's memory cache with aggressive limits to prevent memory bloat
        ImageCache.shared.costLimit = 10 * 1024 * 1024  // 10MB
        ImageCache.shared.countLimit = 50  // Max 50 images in memory
        ImageCache.shared.ttl = 300  // 5 minutes in memory

        // Menu bar apps run for weeks — trim image caches and re-accumulating
        // device data on a 24h cadence, same as the Watch app already does.
        SonosMiniService.shared.onPeriodicCleanup = {
            ImageCache.shared.removeAll()
        }
        SonosMiniService.shared.startPeriodicCleanup()

        // Not while Cue has Sonos switched off: no speakers, and no Local
        // Network prompt for them.
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard CueLink.shared.showsSpeakers else { return }
            try? await SonosMiniService.shared.loadWatch(useCache: true)
        }
    }
    
    var body: some Scene {
        MenuBarExtra {
            GroupMenuScreen()
        } label: {
            MenuBarLabelView()
        }
        .menuBarExtraStyle(.window)
        
        Window("Cue Mini Active", id: "setup") {
            LaunchSplashView()
                .onDisappear {
                    NSApplication.shared.setActivationPolicy(.accessory)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        Window("Setting", id: "settings") {
            MiniSettingsView()
                .onDisappear {
                    NSApplication.shared.setActivationPolicy(.accessory)
                }
        }
        .windowLevel(.normal)
        .windowIdealSize(.fitToContent)
    }

    /// Programmatically clicks the menu bar status item to show/hide the menu
    private static func clickStatusItem() {
        guard let statusItem = NSApp.windows.first(where: { window in
            (window.value(forKey: "statusItem") as? NSStatusItem) != nil
        })?.value(forKey: "statusItem") as? NSStatusItem,
              let button = statusItem.button else {
            return
        }
        button.performClick(nil)
    }
}

/// The status item's label.
///
/// This has to be its own `View`, not an `HStack` inlined into the
/// `MenuBarExtra` label closure: inlined, the reads of `devices` and the
/// settings happen while the `App`'s scene body is being built, which runs once
/// at launch — before `loadWatch` has populated `devices` 200ms later — and is
/// never re-run when an `@Observable` it touched changes. The title never
/// appeared as a result. In a `View`, the same reads are tracked normally and
/// only this label re-renders on a track change.
struct MenuBarLabelView: View {
    private var settings = MiniSettingsService.shared
    private var sonosService = SonosMiniService.shared
    private var link = CueLink.shared

    /// The pinned speaker, when there is one.
    private var pinnedDevice: SonosDevice? {
        guard let pinnedId = settings.pinnedSpeakerId else { return nil }
        return sonosService.devices.first { $0.id == pinnedId }
    }

    /// Pinned speaker if there is one, otherwise whatever is playing.
    ///
    /// `devices` is in discovery order, not the order the menu lists rooms, and
    /// a room can report PLAYING with nothing to show: a soundbar on TV input
    /// has no `dc:title` at all (the codec arrives separately as `tvAudio`), and
    /// an idle or not-yet-resolved room carries `SonosTrack.empty`. Taking the
    /// first playing room blindly lands on one of those and leaves the menu bar
    /// bare while music is playing in another room, so skip the ones with no
    /// title to show.
    private var device: SonosDevice? {
        if let pinnedDevice {
            return pinnedDevice
        }
        return sonosService.devices.first { $0.isPlaying && !$0.isTVMode && !$0.track.song.isEmpty }
    }

    /// A pinned speaker's song, else Cue's while it plays (on this Mac or a
    /// speaker), else a playing speaker's.
    ///
    /// `song`, not `name` — it prefers the stream metadata title and falls back
    /// to `name`, which is what the menu's own rows render.
    private var title: String? {
        guard settings.showSongTitleInMenuBar else { return nil }
        if pinnedDevice == nil, let state = link.state, state.isPlaying, let item = state.item {
            return item.title
        }
        guard let device, !device.isTVMode else { return nil }
        let song = device.track.song
        return song.isEmpty ? nil : song
    }

    var body: some View {
        HStack {
            Image(nsImage: .cueMark)
            if let title {
                Text(title)
            }
        }
        .animation(.spring, value: title)
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
