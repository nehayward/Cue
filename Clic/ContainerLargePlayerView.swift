import SwiftUI
import SonosKit

struct ContainerLargePlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var id: String?

    var body: some View {
        Group {
            @Bindable var sonosService = sonosService
            if let id, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                LargePlayerView(group: $sonosService.sorted[group])
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}
