import SwiftUI
import SonosKit

struct ZoneView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom

    var body: some View {
        VStack(alignment: .leading) {
            Text(group.coordinatorRoom.track.name)
            Text(group.coordinatorRoom.track.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(alignment: .top)
        .fontDesign(.rounded)
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
