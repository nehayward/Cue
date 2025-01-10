import Cocoa
import SwiftUI
import SonosKitMini
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemManager = StatusItemManager()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItemManager.createStatusItem()
        
        KeyboardShortcuts.onKeyUp(for: .toggleClicMini) { [self] in
            statusItemManager.toggleGroupMenu()
        }
        
        Task {
            try await SonosMiniService.shared.load(useCache: true, keyPaths: [\.coordinatorRoom])
        }
    }
}
