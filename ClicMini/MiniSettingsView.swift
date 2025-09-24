import SwiftUI
import KeyboardShortcuts

struct MiniSettingsView: View {
    @State private var settingsService = MiniSettingsService.shared
    
    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $settingsService.launchAtLogin)
                .onChange(of: settingsService.launchAtLogin) { _, newValue in
                    Task {
                        try? await settingsService.setLaunchAtLoginEnabled(newValue)
                    }
                }
                .toggleStyle(.switch)
            Section("Keyboard Shortcuts") {
                KeyboardShortcuts.Recorder(for: .toggleClicMini) {
                    Text("Show/Hide Clic Mini")
                    Text("Use this shortcut to quickly show/hide the Clic Mini menu from anywhere.")
                }
                
                KeyboardShortcuts.Recorder(for: .volumeUp) {
                    Text("Volume Up")
                    Text("Increase volume of playing group")
                }
                
                KeyboardShortcuts.Recorder(for: .volumeDown) {
                    Text("Volume Down")
                    Text("Decrease volume of playing group")
                }
                
                KeyboardShortcuts.Recorder(for: .nextTrack) {
                    Text("Next Track")
                    Text("Skip to next track on playing speaker")
                }
                
                KeyboardShortcuts.Recorder(for: .previousTrack) {
                    Text("Previous Track")
                    Text("Go to previous track on playing speaker")
                }
            }
            
//            VStack(alignment: .leading, spacing: 20) {
//                VStack(alignment: .leading, spacing: 12) {
//                    Text("General")
//                        .font(.headline)
//                   
//                }
//                
//                VStack(alignment: .leading, spacing: 12) {
//                    Text("Keyboard Shortcuts")
//                        .font(.headline)
//                    VStack(alignment: .leading, spacing: 8) {
//                        KeyboardShortcuts.Recorder("Toggle Clic Mini:", name: .toggleClicMini)
//                        Text("Use this shortcut to quickly show/hide the Clic Mini menu from anywhere.")
//                            .font(.caption)
//                            .foregroundStyle(.secondary)
//                    }
//                }
//                
//            }
//            .padding()

        }
        .frame(width: 400, height: 480)
        .formStyle(.grouped)
    }
}

#Preview {
    MiniSettingsView()
}
