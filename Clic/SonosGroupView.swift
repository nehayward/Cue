import SwiftUI
import SonosKit

struct SonosGroupView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @State var group: GroupRoom

    var body: some View {
        Section {
            HStack(alignment: .top) {
                ArtworkView(group: group)
                    .frame(width: 72, height: 72)
                ZoneView(group: group)
            }
        }
        .tag(group.coordinatorID)
        .task {
            await sonosService.load()
            group = sonosService.groups.first!
        }
    }
}

#Preview {
    List {
        SonosGroupView(group: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "", name: "Kitchen")]))
            .environment(SonosService())
    }
}

