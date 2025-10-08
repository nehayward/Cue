import SwiftUI
import SonosKitMini
import KeyboardShortcuts

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
    private let globalMediaControlService = GlobalMediaControlService.shared
    private var sonosServiceMini = SonosMiniService.shared
    private var miniSettingsService = MiniSettingsService.shared

    init() {
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
        sonosServiceMini.onTrackChanged = { group, track in
            Task { @MainActor in
                // Only show HUD if setting is enabled and menu is not visible
                if MiniSettingsService.shared.showTrackChangeHUD && !MenuVisibilityService.shared.isMenuVisible {
                    HudWindowManager.shared.extendVisibility()
                    
                    // Show track change indicator
                    HudWindowManager.shared.showMediaIndicator(
                        speakerName: group.nameWithCount,
                        action: .nextTrack(trackName: track.name, imageURL: track.sonosAlbumArtURL),
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
                if miniSettingsService.showSongTitleInMenuBar {
                    // Show track name from pinned speaker if available, otherwise show first device
                    if let pinnedId = miniSettingsService.pinnedSpeakerId,
                       let pinnedDevice = sonosServiceMini.devices.first(where: { $0.id == pinnedId }) {
                        Text(pinnedDevice.track.name)
                            .animation(.spring, value: pinnedDevice.track.id)
                    } else if let device = sonosServiceMini.devices.first(where: { $0.isPlaying }) {
                        Text(device.track.name)
                            .animation(.spring, value: device.track.id)
                    }
                }
            }
        }
        .menuBarExtraStyle(.window)
        
        Window("Setting", id: "settings") {
            MiniSettingsView()
                .frame(width: 200, height: 300)
                .onDisappear {
                    NSApplication.shared.setActivationPolicy(.accessory)
                }
        }
        .windowLevel(.normal)
        .windowIdealSize(.fitToContent)
    }
}
