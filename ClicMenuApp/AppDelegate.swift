import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemManager = StatusItemManager()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItemManager.createStatusItem()
    }
}

