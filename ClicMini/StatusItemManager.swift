import Combine
import SwiftUI
import SonosKit

final class StatusItemManager {
    private var statusItem: NSStatusItem?

    private var sizePassthrough = PassthroughSubject<CGSize, Never>()
    private var sizePassthroughWindow = PassthroughSubject<CGSize, Never>()
    private var sizeCancellable: AnyCancellable?
    private var sizeCancellableWindow: AnyCancellable?

    func createStatusItem() {
        let statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button!.target = self
        statusItem.button!.action = #selector(triggerStatus)
        statusItem.button!.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.image = NSImage(systemSymbolName: "hifispeaker.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))

        // MARK: With selected group
//        statusItem.button?.frame = hostingView.frame
//        statusItem.button?.addSubview(hostingView)
//        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
//        sizeCancellable = sizePassthrough.sink { [weak self] size in
//            let frame = NSRect(origin: .zero, size: .init(width: size.width, height: 24))
//            self?.hostingView?.frame = frame
//            self?.statusItem?.button?.frame = frame
//        }
////        
//        let menu = NSMenu()
//        let menuItem = NSMenuItem()
//        menuItem.view = contentView
//        menu.addItem(menuItem)
//        
//        statusItem.button?.menu = menu
        //        self.hostingView = hostingView
        self.statusItem = statusItem
        sizeCancellableWindow = sizePassthroughWindow.sink { [weak self] size in
            let frame = NSRect(origin: .zero, size: .init(width: size.width, height: size.height))
            self?.statusItem?.menu?.items.first?.view?.frame = frame
            print(frame)
        }
    }
    
    @objc private func triggerStatus(_ button: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
            
        switch event.type {
        case .rightMouseUp:
            let alternateMenu = NSMenu()
            let refreshItem = NSMenuItem(title: "Refresh Devices", action: #selector(refreshDevices), keyEquivalent: "r")
            refreshItem.target = self
            alternateMenu.addItem(refreshItem)
            
            let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            alternateMenu.addItem(quitItem)
            
            statusItem?.menu = alternateMenu
            statusItem?.button?.performClick(nil)
            
            statusItem?.menu = nil
        case .leftMouseUp:
            let contentView = NSHostingView(rootView: GroupMenuScreen(sizePassthrough: sizePassthroughWindow).environment(SonosService.shared))
            
            let menu = NSMenu()
            let menuItem = NSMenuItem()
            menuItem.view = contentView
            menu.addItem(menuItem)

            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
            
        default:
            break
        }
    }
    
    @MainActor
    @objc private func refreshDevices() {
        Task {
            try? await SonosService.shared.load(useCache: true)
        }
    }
}

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct StatusItem: View {
    @State var sonosService = SonosService.shared
    var sizePassthrough: PassthroughSubject<CGSize, Never>
    
    @ViewBuilder
    var mainContent: some View {
        HStack(alignment: .center) {
            Image(systemName: "hifispeaker.fill")
                .resizable()
                .bold()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
//                .resizable()
      
//            if let group = sonosService.selectedGroup {
//                Text(group.nameWithCount)
//                    .fixedSize()
//                Button {
//                    Task {
//                        await sonosService.togglePlayback(ip: group.ip)
//                    }
//                } label: {
//                    Image(systemName: "play.fill")
//                }
//                .buttonStyle(.plain)
//            } else {
//                Text("Select Group")
//                    .fixedSize()
//            }
        }
        .onAppear {
            SonosService.shared.monitor()
        }
        .fontDesign(.rounded)
        .padding(.horizontal, 12)
    }
    
    var body: some View {
        mainContent
            .overlay(
                GeometryReader { geometryProxy in
                    Color.clear
                        .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
                }
            )
            .onPreferenceChange(SizePreferenceKey.self) { size in
                sizePassthrough.send(size)
            }
    }
}
