import SwiftUI
import SonosKitMini
import KeyboardShortcuts
import Kingfisher

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
struct ClicMiniApp: App {
    // Don't store singletons as properties - access directly via .shared
    // This prevents unnecessary strong references and memory retention
    
    init() {
        // Initialize global services to ensure they're set up
        _ = GlobalMediaControlService.shared
        _ = SonosMiniService.shared
        _ = MiniSettingsService.shared
        
        KeyboardShortcuts.onKeyUp(for: .toggleClicMini) {
            guard let statusItem = NSApp.windows.first(where: { window in
                (window.value(forKey: "statusItem") as? NSStatusItem) != nil
            })?.value(forKey: "statusItem") as? NSStatusItem,
                  let button = statusItem.button else {
                // Could not find statusItem or its button; safely do nothing
                return
            }
            button.performClick(nil)
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
                        action: .nextTrack(trackName: track.name, albumName: track.album, imageURL: track.sonosAlbumArtURL),
                        isPlaying: true
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
        
        // Configure KingFisher image cache with aggressive limits to prevent memory bloat
        ImageCache.default.memoryStorage.config.totalCostLimit = 10 * 1024 * 1024  // 10MB
        ImageCache.default.memoryStorage.config.countLimit = 50  // Max 50 images in memory
        ImageCache.default.memoryStorage.config.expiration = .seconds(300)  // 5 minutes in memory
        ImageCache.default.diskStorage.config.sizeLimit = 20 * 1024 * 1024  // 20MB
        ImageCache.default.diskStorage.config.expiration = .days(1)

        Task {
            try? await Task.sleep(for: .milliseconds(200))
            try? await SonosMiniService.shared.loadWatch(useCache: true)
        }
    }
    
    var body: some Scene {
        MenuBarExtra {
            GroupMenuScreen()
        } label: {
            HStack {
                let image = NSImage.clicIcon.withSymbolConfiguration(.init(pointSize: 32, weight: .black))
                Image(nsImage: image!)
                // Show track name only if the setting is enabled
                // Access services directly via .shared to avoid retaining references
                if MiniSettingsService.shared.showSongTitleInMenuBar {
                    // Show track name from pinned speaker if available, otherwise show first device
                    if let pinnedId = MiniSettingsService.shared.pinnedSpeakerId,
                       let pinnedDevice = SonosMiniService.shared.devices.first(where: { $0.id == pinnedId }) {
                        Text(pinnedDevice.track.name)
                            .animation(.spring, value: pinnedDevice.track.id)
                    } else if let device = SonosMiniService.shared.devices.first(where: { $0.isPlaying }) {
                        Text(device.track.name)
                            .animation(.spring, value: device.track.id)
                    }
                }
            }
        }
        .menuBarExtraStyle(.window)
        
        Window("Clic Mini Active", id: "setup") {
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
}
