import Cocoa
import SwiftUI
import SonosKitMini
import KeyboardShortcuts
import Kingfisher

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemManager = StatusItemManager()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItemManager.createStatusItem()
        
        KeyboardShortcuts.onKeyUp(for: .toggleClicMini) { [self] in
            statusItemManager.toggleGroupMenu()
        }
        
        Task {
            try await SonosMiniService.shared.load(useCache: true)
        }
        
        // Configure Kingfisher cache size (50MB)
        ImageCache.default.memoryStorage.config.totalCostLimit = 50 * 1024 * 1024   
    }
}
