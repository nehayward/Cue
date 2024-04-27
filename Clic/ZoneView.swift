import SwiftUI
import SonosKit

struct ZoneView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom

    var body: some View {
        VStack(alignment: .leading) {
            Text(group.coordinatorRoom.track.name)
                .foregroundStyle(.primary)
                .tint(.primary)
                .lineLimit(1, reservesSpace: true)
            Text(group.coordinatorRoom.track.artist)
                .font(.callout)
                .foregroundStyle(.secondary)
                .tint(.secondary)
                .lineLimit(1, reservesSpace: true)

            // MARK: DEBUG Only
//            Text(group.playbackService.title)
//            Text(group.availableActions.description)
//            Text(group.coordinatorRoom.track.id)
//                .font(.callout)
//                .foregroundStyle(.secondary)
//                .tint(.secondary)
//                .lineLimit(1)
//            Text(group.coordinatorRoom.track.artworkURL?.absoluteString ?? "")
//                .font(.callout)
//                .foregroundStyle(.secondary)
//                .tint(.secondary)
//                .lineLimit(1)
//                .onAppear {
//                    print(group.coordinatorRoom.track.artworkURL?.absoluteString)
//                }

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
