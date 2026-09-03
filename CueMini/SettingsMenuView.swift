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
                Label("Toggle Showing Cue Mini \(KeyboardShortcuts.getShortcut(for: .toggleCueMini)?.description ?? "")", systemImage: "globe")
                Text("Configure in Settings")
            }
            
            Toggle(isOn: $launchAtLogin) {
                Label("Launch at Login", systemImage: "person.crop.circle.fill.badge.checkmark")
            }
            .onChange(of: launchAtLogin) {
                toggleLaunchAtLogin()
            }

            Button {
                NSApplication.shared.terminate(self)
            } label: {
                Label("Quit", systemImage: "xmark.rectangle")
            }
        } label: {
            Image(systemName: "gear")
                .font(.title)
        }
        .menuIndicator(.hidden)
        .modifier(SettingsMenuStyleModifier())
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

struct SettingsMenuStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonBorderShape(.circle)
                .foregroundStyle(.accent)
                .controlSize(.extraLarge)
        } else {
            content
                .menuStyle(.borderlessButton)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    MiniSettingsView()
}
