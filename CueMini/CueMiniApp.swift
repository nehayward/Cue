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

        // Once the app has started: NSStatusBar needs it.
        Task { @MainActor in
            StatusItemManager.shared.start()
        }

        KeyboardShortcuts.onKeyUp(for: .toggleCueMini) {
            StatusItemManager.shared.togglePanel()
        }

        // Listen for show menu requests from main Cue app
        DistributedNotificationCenter.default().addObserver(
            forName: Self.showMenuNotification,
            object: nil,
            queue: .main
        ) { _ in
            StatusItemManager.shared.togglePanel()
        }

        // Check for --show-menu launch argument
        if CommandLine.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                StatusItemManager.shared.togglePanel()
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
    
    /// A scene for SwiftUI to have, which opens nothing: the item and its panel
    /// are `StatusItemManager`'s, and Settings is `WindowManager`'s.
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
