import SwiftUI
import SonosKit
import WatchConnectivity

struct DebugScreen: View {
    @State var sonosSearch = SonosSearch()
    

    var body: some View {
        Text(sonosSearch.lastKnownIP)
            .task {
                try? await sonosSearch.getFirstIP()
            }
            .onAppear {
                sonosSearch.ssdp()
            }
            .onAppear {
                try? WCSession.default.updateApplicationContext(["Group": "!23"])
            }
    }
}
