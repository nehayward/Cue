import SwiftUI
import SonosKitMini
import KeyboardShortcuts

@main
struct ClicMiniApp: App {
    private let globalMediaControlService = GlobalMediaControlService.shared
    
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
            let image = NSImage(named: "clic.icon")?.withSymbolConfiguration(.init(pointSize: 32, weight: .black))
            Image(nsImage: image!)
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
