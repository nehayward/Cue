import SwiftUI
import SonosKit

struct ZoneView: View {
    @Binding var group: GroupRoom

    var body: some View {
        VStack(alignment: .leading) {
            Text(group.coordinatorRoom.track.song)
                .foregroundStyle(.primary)
                .tint(.primary)
                .lineLimit(1, reservesSpace: true)
            Text(group.coordinatorRoom.track.artist)
                .font(.callout)
                .foregroundStyle(.secondary)
                .tint(.secondary)
                .lineLimit(1, reservesSpace: true)

        }
        .frame(alignment: .top)
        .fontDesign(.rounded)
    }
}

//#Preview {
//    List {
//        Section {
//            ZoneView(group: .constant(.garage))
//        }
//        Section {
//            ZoneView(group: .constant(.theater))
//        }
//    }
//    .environment(SonosService())
//}
