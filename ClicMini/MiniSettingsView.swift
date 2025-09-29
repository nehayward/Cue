import SwiftUI
import KeyboardShortcuts
import SonosKitMini

struct MiniSettingsView: View {
    @State private var settingsService = MiniSettingsService.shared
    @State private var sonosServiceMini = SonosMiniService.shared
    
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
            
            Section("Pinned Speaker") {
                VStack(alignment: .leading, spacing: 8) {
                    if let pinnedId = settingsService.pinnedSpeakerId,
                       let pinnedDevice = sonosServiceMini.devices.first(where: { $0.id == pinnedId }) {
                        HStack {
                            Image(systemName: "pin.fill")
                                .foregroundStyle(.accent)
                            Text("Currently pinned: \(pinnedDevice.nameWithCount)")
                                .fontWeight(.medium)
                            Spacer()
                            Button("Unpin") {
                                settingsService.unpinSpeaker()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else {
                        HStack {
                            Image(systemName: "pin")
                                .foregroundStyle(.secondary)
                            Text("No speaker pinned")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text("Pin a speaker from the main menu to prioritize it for menu bar display and keyboard shortcuts. Pinned speakers will show their track name in the menu bar and receive all media control commands.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("Keyboard Shortcuts") {
                KeyboardShortcuts.Recorder(for: .toggleClicMini) {
                    Text("Show/Hide Clic Mini")
                    Text("Use this shortcut to quickly show/hide the Clic Mini menu from anywhere.")
                }
                
                KeyboardShortcuts.Recorder(for: .volumeUp) {
                    Text("Volume Up")
                    Text("Increase volume of pinned speaker (or currently playing group)")
                }
                
                KeyboardShortcuts.Recorder(for: .volumeDown) {
                    Text("Volume Down")
                    Text("Decrease volume of pinned speaker (or currently playing group)")
                }
                
                KeyboardShortcuts.Recorder(for: .nextTrack) {
                    Text("Next Track")
                    Text("Skip to next track on pinned speaker (or currently playing speaker)")
                }
                
                KeyboardShortcuts.Recorder(for: .previousTrack) {
                    Text("Previous Track")
                    Text("Go to previous track on pinned speaker (or currently playing speaker)")
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
