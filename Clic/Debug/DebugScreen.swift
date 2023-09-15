import SwiftUI
import SonosKit
import WatchConnectivity

struct DebugScreen: View {
    @State var sonosSearch = SonosSearch()
    @Environment(SonosService.self) var sonosService: SonosService

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
            .safeAreaInset(edge: .top) {
                Text("State: \(sonosService.state)")
                    .fontDesign(.rounded)
                    .fontWidth(.compressed)
                    .foregroundStyle(Color.accentColor.gradient)
                    .padding()
                    .background(.thickMaterial)
                    .clipShape(Capsule())
            }
    }
}
