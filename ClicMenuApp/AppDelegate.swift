import Cocoa
import SwiftUI
import SonosKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemManager = StatusItemManager()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItemManager.createStatusItem()
    }
}

