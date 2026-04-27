import SwiftUI
import SonosKit

struct GroupVolumeControlView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom

    @State var isEditingGroupVolume = false
    @State var isEditingRoomVolume = false
    @State var subviewHeight: CGFloat = 0

    @Binding var isExpanded: Bool
    @State private var volumeTask: Task<Void, Error>?

    var body: some View {
        VStack {
            VolumeControlView(group: group)
                .frame(height: 40)
            VStack {
                ForEach(group.rooms) { room in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(room.name)
                            .fontDesign(.rounded)
                            .bold()
                        RoomVolumeView(room: room) {
                            volumeTask?.cancel()
                            volumeTask = Task {
                                try await Task.sleep(for: .milliseconds(300))
                                try Task.checkCancellation()
                                await sonosService.snapShotGroup(ip: group.coordinatorRoom.ip)
                            }
                        }
                    }
                }
                Button {
                    for room in group.rooms {
                        Task {
                            await sonosService.setDeviceVolume(ip: room.ip, volume: Int(group.groupVolume))
                        }
                    }
                    Task {
                        try await Task.sleep(for: .seconds(1))
                        await sonosService.snapShotGroup(ip: group.coordinatorRoom.ip)
                    }
                } label: {
                    Text("Sync Volume")
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxWidth: 500)
            }
            .opacity(isExpanded ? 1 : 0)
            .scaleEffect(x: isExpanded ? 1 : 0.9)
        }
        .background(GeometryReader {
            Color.clear.preference(key: ViewHeightKey.self,
                                   value: $0.frame(in: .local).size.height)
        })
        .onPreferenceChange(ViewHeightKey.self) { subviewHeight = $0 }
        .frame(height: isExpanded ? subviewHeight : 40, alignment: .top)
        .clipped()
        .frame(maxWidth: 500)
    }

    struct ViewHeightKey: PreferenceKey {
        static var defaultValue: CGFloat { 0 }
        static func reduce(value: inout Value, nextValue: () -> Value) {
            value = value + nextValue()
        }
    }
}

#Preview {
    GroupVolumeControlView(group: .constant(.garagePlusTheater), isExpanded: .constant(true))
        .environment(SonosService())

}

#Preview {
    GroupVolumeControlView(group: .constant(.garagePlusTheater), isExpanded: .constant(false))
        .environment(SonosService())

}

