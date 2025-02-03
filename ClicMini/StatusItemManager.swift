import Combine
import SwiftUI
import SonosKitMini
import KeyboardShortcuts

final class StatusItemManager {
    private lazy var menuBarViewHost = NSHostingView(rootView: MenuBarView(sizePassthrough: sizePassthrough))
    private var statusItem: NSStatusItem?
    
    private var sizePassthrough = PassthroughSubject<CGSize, Never>()
    private var sizePassthroughWindow = PassthroughSubject<CGSize, Never>()
    
    private var sizeCancellable: AnyCancellable?
    private var sizeCancellableWindow: AnyCancellable?
    
    func createStatusItem() {
        if statusItem != nil { return }
        let statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button!.target = self
        statusItem.button!.action = #selector(triggerStatus)
        statusItem.button!.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.image = NSImage(named: "clic.icon")?.withSymbolConfiguration(.init(pointSize: 32, weight: .black))
        
        // MARK: SwiftUI Menubar View
        //        // Add the hosting view for SwiftUI content
//        statusItem.button?.frame = menuBarViewHost.frame
//        statusItem.button?.addSubview(menuBarViewHost)
//        
//        sizeCancellable = sizePassthrough.sink { [weak self] size in
//            print("Sizing")
//            let frame = NSRect(origin: .zero, size: .init(width: size.width, height: 24))
//            self?.menuBarViewHost.frame = frame
//            self?.statusItem?.button?.frame = frame
//        }
        //
        //        self.hostingView = hostingView
        self.statusItem = statusItem
        sizeCancellableWindow = sizePassthroughWindow.sink { [weak self] size in
            print(" CHANGING SiZE WINDOW _______________")
            let frame = NSRect(origin: .zero, size: .init(width: size.width, height: size.height))
            self?.statusItem?.menu?.items.first?.view?.frame = frame
            print(frame)
        }
        
        Task {
            await SonosMonitor.shared.startListening()
        }
    }
    
    
    @MainActor @objc private func triggerStatus(_ button: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        switch event.type {
        case .rightMouseUp:
            handleRightClick()
        case .leftMouseUp:
            toggleGroupMenu()
        default:
            break
        }
    }
    
    @MainActor private func handleRightClick() {
        let alternateMenu = NSMenu()
        
        let toggleClicMini = NSMenuItem()
        toggleClicMini.title = "Toggle Clic Mini"
        toggleClicMini.target = self
        toggleClicMini.action = #selector(toggleGroupMenu)
        toggleClicMini.setShortcut(for: .toggleClicMini)
        alternateMenu.addItem(toggleClicMini)
        
        // Add separator
        alternateMenu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        alternateMenu.addItem(quitItem)
        
        statusItem?.menu = alternateMenu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc func toggleGroupMenu() {
        if statusItem?.menu != nil {
            statusItem?.menu?.cancelTracking()
            statusItem?.menu = nil
        } else {
            let contentView = NSHostingView(rootView: GroupMenuScreen(sizePassthroughWindow: sizePassthroughWindow).environment(SonosMiniService.shared))
            
            let menu = NSMenu()
            let menuItem = NSMenuItem()
            menuItem.view = contentView
            menu.addItem(menuItem)
            
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        }
        
    }
}

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
