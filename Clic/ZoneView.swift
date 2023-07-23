import SwiftUI
import SonosKit

struct ZoneView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    var group: GroupRoom

    var body: some View {
        VStack(alignment: .leading) {
            Text(group.coordinatorRoom.track.name)
            Text(group.coordinatorRoom.track.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fontDesign(.rounded)
    }
}

#Preview {
    List {
        Section {
            ZoneView(group: GroupRoom(id: "", coordinatorID: "Kitchen", rooms: [Room(id: "Kitchen", ip: "192", name: "Kitchen")]))
                .environment(SonosService())
        }
        Section {
            ZoneView(group: GroupRoom(id: "", coordinatorID: "Garage", rooms: [Room(id: "Garage", ip: "192", name: "Garage"), Room(id: "Kitchen", ip: "192", name: "Kitchen")]))
                .environment(SonosService())
        }
    }
}
