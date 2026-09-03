import SwiftUI
import SonosKit

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
