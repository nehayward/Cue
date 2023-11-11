import SwiftUI
import SonosKit

struct PlayerScreen: View {
    @Binding var group: GroupRoom

    var body: some View {
        if group.tvMode {
            TVView(group: $group)
        } else {
            PlayerView(group: $group)
        }
        QueueScreen(group: $group)
        if group.rooms.count > 1 {
            GroupVolumeControlScreen(group: $group)
        }
    }
}

#Preview {
    NavigationStack {
        PlayerScreen(group: .constant(.garage))
            .environment(SonosService())
            .environment(Popover())

    }
}

