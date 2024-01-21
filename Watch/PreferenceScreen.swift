import SwiftUI
import SonosKit

struct PreferenceScreen: View {
    @State private var router = Router()
    @State private var showSubscriptions = false

    @AppStorage("com.clic.autoLaunchNowPlaying", store: UserDefaults(suiteName: "group.com.clic")) private var autoLaunchNowPlaying: Bool = false

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

