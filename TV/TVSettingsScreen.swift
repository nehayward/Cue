import SwiftUI
import SonosKit
import SubscriptionKit
import CloudStorage
import VibesDS

struct TVSettingsScreen: View {
    @AppStorage("disableScreenSaver") var disableScreenSaver = false

    var body: some View {
        NavigationStack {
            List {
                Toggle(isOn: $disableScreenSaver) {
                    Text("Keep Screen Awake")
                    Text("Prevent screen from dimming or sleeping")
                }
            }
        }.onChange(of: disableScreenSaver) {
            UIApplication.shared.isIdleTimerDisabled = disableScreenSaver
        }
        .background(.thickMaterial)
    }
}
