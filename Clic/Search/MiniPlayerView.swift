import SwiftUI
import SonosKit

struct MiniPlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    var groupID: String?

    var body: some View {
        @Bindable var sonosService = sonosService
        if let groupID, let groupIndex = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }) {
            let group = $sonosService.sorted[groupIndex]
            HStack(alignment: .top) {
                ArtworkView(group: group)
                    .frame(width: 40, height: 40)
                ZoneView(group: group)
            }
            .padding(.horizontal)
        } else {
            Text("No Group")
        }
    }
}

#Preview {
    List {
        Section {
            ZoneView(group: .constant(.garage))
        }
        Section {
            ZoneView(group: .constant(.theater))
        }
    }
    .environment(SonosService())
}
