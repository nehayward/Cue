import SwiftUI
import KeyboardShortcuts
import ServiceManagement

struct SettingsMenuView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = false
    
    var body: some View {
        Menu {
            Button {
//                NSApp.setActivationPolicy(.regular)
//                NSApplication.shared.activate(ignoringOtherApps: true)
//                // Switch to regular activation policy so the window can be focused
//                openWindow(id: "settings")
//                
                WindowManager.shared.openPreferences()
            } label: {
                Label("Open Settings", systemImage: "gear")
            }
            Button {
                
            } label: {
                Label("Toggle Showing Clic Mini \(KeyboardShortcuts.getShortcut(for: .toggleClicMini)?.description ?? "")", systemImage: "globe")
                Text("Configure in Settings")
            }
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) {
                    toggleLaunchAtLogin()
                }
            Button {
                NSApplication.shared.terminate(self)
            } label: {
                Text("Quit")
            }
        } label: {
            Image(systemName: "gear")
                .font(.title)
        }
        .menuIndicator(.hidden)
        .buttonBorderShape(.circle)
        .foregroundStyle(.accent)
        .controlSize(.extraLarge)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
    
    private func toggleLaunchAtLogin() {
        Task {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try await setLaunchAtLoginEnabled(false)
                } else {
                    try await setLaunchAtLoginEnabled(true)
                }
            } catch {
                print("Error toggling launch at login: ", error)
            }
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) async throws {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? await SMAppService.mainApp.unregister()
        }
    }
    
    private func openPreferences() {
        WindowManager.shared.openPreferences()
    }
}

#Preview {
    MiniSettingsView()
}
