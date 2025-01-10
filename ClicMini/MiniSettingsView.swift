import SwiftUI

struct MiniSettingsView: View {
    @AppStorage("launchAtStartup") private var launchAtStartup = false
    @AppStorage("defaultVolume") private var defaultVolume = 50.0
    
    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at startup", isOn: $launchAtStartup)
            }
            
            Section("Audio") {
                VStack(alignment: .leading) {
                    Text("Default Volume")
                    Slider(value: $defaultVolume, in: 0...100) {
                        Text("Default Volume")
                    }
                    Text("\(Int(defaultVolume))%")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 350, height: 200)
    }
}

#Preview {
    MiniSettingsView()
}
