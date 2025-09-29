import SwiftUI
import SonosKitMini
import KeyboardShortcuts

@main
struct ClicMiniApp: App {
    private let globalMediaControlService = GlobalMediaControlService.shared
    private var sonosServiceMini = SonosMiniService.shared
    private var miniSettingsService = MiniSettingsService.shared

    init() {
        KeyboardShortcuts.onKeyUp(for: .toggleClicMini) {
            let statusItem = NSApp.windows.first?.value(forKey: "statusItem") as? NSStatusItem
            statusItem?.button?.performClick(nil)
        }
        
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let statusItem = NSApp.windows.first?.value(forKey: "statusItem") as? NSStatusItem
            statusItem?.button?.performClick(nil)
        }
        #endif
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
