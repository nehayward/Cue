import SwiftUI
import KeyboardShortcuts
import SonosKitMini

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
            
            Toggle("Show song title in menu bar", isOn: $settingsService.showSongTitleInMenuBar)
                .toggleStyle(.switch)
            
            Toggle("Show track change notifications", isOn: $settingsService.showTrackChangeHUD)
                .toggleStyle(.switch)
            
            Section("Keyboard Shortcuts") {
                KeyboardShortcuts.Recorder(for: .toggleCueMini) {
                    Text("Show/Hide Cue Mini")
                    Text("Use this shortcut to quickly show/hide the Cue Mini menu from anywhere.")
                }
                
                KeyboardShortcuts.Recorder(for: .volumeUp) {
                    Text("Volume Up")
                    Text("Increase the volume of the group Cue plays on, else the group playing")
                }
                
                KeyboardShortcuts.Recorder(for: .volumeDown) {
                    Text("Volume Down")
                    Text("Decrease the volume of the group Cue plays on, else the group playing")
                }
                
                KeyboardShortcuts.Recorder(for: .nextTrack) {
                    Text("Next Track")
                    Text("Skip to the next track in Cue's player")
                }
                
                KeyboardShortcuts.Recorder(for: .previousTrack) {
                    Text("Previous Track")
                    Text("Go to the previous track in Cue's player")
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
//                        KeyboardShortcuts.Recorder("Toggle Cue Mini:", name: .toggleCueMini)
//                        Text("Use this shortcut to quickly show/hide the Cue Mini menu from anywhere.")
//                            .font(.caption)
//                            .foregroundStyle(.secondary)
//                    }
//                }
//                
//            }
//            .padding()

        }
        .frame(width: 400, height: 700)
        .formStyle(.grouped)
    }
}

#Preview {
    MiniSettingsView()
}
