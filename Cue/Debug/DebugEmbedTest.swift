import SwiftUI
import SonosKit

struct DebugEmbedTest: View {
    var sonosService: SonosService
    @Binding var group: GroupRoom

    var body: some View {
        VStack(alignment: .leading) {
            Text(group.coordinatorRoom.track.name)
            Text(group.coordinatorRoom.track.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(group.coordinatorRoom.isPlaying ? "True" : "False")")
        }
        .frame(alignment: .top)
        .fontDesign(.rounded)
    }
}
