import SwiftUI
import SonosKit

struct PlayerScreen: View {
    @Bindable var group: GroupRoom

    var body: some View {
        TabView {
            PlayerView(group: group)
            if group.rooms.count > 1 {
                GroupVolumeControlScreen(group: group)
            }
        }
    }
}

#Preview {
    NavigationStack {
        PlayerScreen(group: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "192.168.4.50", name: "Garage")]))
            .environment(SonosService())
            .environment(Popover())

    }
}

