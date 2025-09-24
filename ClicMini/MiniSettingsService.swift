import Combine
import Foundation
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

@Observable
@MainActor
final class MiniSettingsService {
    static let shared = MiniSettingsService()
    
    var launchAtLogin: Bool = false
    var defaultVolume: Double = 50.0 {
        didSet {
            UserDefaults.standard.set(defaultVolume, forKey: "defaultVolume")
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Load initial values
        loadSettings()
        
        // Monitor SMAppService status changes
        setupLaunchAtLoginMonitoring()
    }
    
    private func loadSettings() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        defaultVolume = UserDefaults.standard.double(forKey: "defaultVolume")
        if defaultVolume == 0 {
            defaultVolume = 50.0
            UserDefaults.standard.set(defaultVolume, forKey: "defaultVolume")
        }
    }
    
    private func setupLaunchAtLoginMonitoring() {
        // Check status periodically or when app becomes active
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Launch at Login
    
    func toggleLaunchAtLogin() async {
        do {
            if launchAtLogin {
                try await setLaunchAtLoginEnabled(false)
            } else {
                try await setLaunchAtLoginEnabled(true)
            }
        } catch {
            print("Error toggling launch at login: ", error)
        }
    }
    
    func setLaunchAtLoginEnabled(_ enabled: Bool) async throws {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? await SMAppService.mainApp.unregister()
        }
        
        // Update published property
        await MainActor.run {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
    
    // MARK: - Keyboard Shortcuts
    
    func getShortcutDescription() -> String {
        if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleClicMini) {
            return shortcut.description
        }
        return "Not set"
    }
}

// MARK: - AppStorage Wrappers for SwiftUI

struct MiniSettingsAppStorage {
    @AppStorage("launchAtStartup") static var launchAtStartup = false
    @AppStorage("defaultVolume") static var defaultVolume = 50.0
}
