import SwiftUI
import SonosKit

struct DeviceNameView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    var group: GroupRoom

    var body: some View {
        HStack {
            Image(systemName: "hifispeaker.fill")
                .symbolRenderingMode(.hierarchical)
                .fontDesign(.rounded)
            Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
        }
        .fontDesign(.rounded)
        .font(.body)
    }
}

#Preview {
    List {
        DeviceNameView(group: .garage)
            .environment(SonosService())
    }
}

