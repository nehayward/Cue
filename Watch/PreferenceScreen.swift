import CloudStorage
import SwiftUI
import SonosKit

struct PreferenceScreen: View {
    @CloudStorage("com.clic.autoLaunchNowPlaying") private var autoLaunchNowPlaying: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $autoLaunchNowPlaying) {
                        Text("Auto Launch Group")
                    }
                    .tint(.accent)
                } footer: {
                    Text("Instantly jump to the group currently playing.")
                }
            }
        }
    }
}


#Preview {
    PreferenceScreen()
        .withEnvironments()
        .onAppear {
            SonosService.shared.monitor()
        }
}

