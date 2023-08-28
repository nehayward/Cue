import UIKit
import SwiftUI
import SonosKit

struct GroupVolumeControlScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Bindable var group: GroupRoom

    @State var isEditingGroupVolume = false
    @State var isEditingRoomVolume = false

    init(group: GroupRoom) {
        self.group = group
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                HStack {
                    Text("Group Volume")
                        .fontDesign(.rounded)
                        .font(.caption)
                    Spacer()
                    Text("\(group.groupVolume, specifier: "%03.0f")%")
                        .monospacedDigit()
                }
                HStack {
                    Slider(value: $group.groupVolume, in: 0...100, step: 2) { isEditing in
                        self.isEditingGroupVolume = isEditing
                    }
                    .sensoryFeedback(.impact(flexibility: .solid), trigger: group.groupVolume, condition: { oldValue, newValue in
                        return !isEditingGroupVolume
                    })
                    .animation(.snappy, value: group.groupVolume)
                    .onChange(of: group.groupVolume) {
                        if isEditingGroupVolume {
                            Task {
                                await sonosService.setGroupVolume(ip: group.coordinatorRoom.ip, volume: Int(group.groupVolume))
                            }
                        }
                    }
                }
                
                VStack {
                    ForEach($group.rooms) { $room in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(room.name)
                                    .fontDesign(.rounded)
                                    .font(.caption)
                                Spacer()
                                Text("\(room.volume, specifier: "%03.0f")%")
                                    .monospacedDigit()
                            }
                            Slider(value: $room.volume, in: 0...100, step: 2) { isEditing in
                                self.isEditingRoomVolume = isEditing
                            }
                            .sensoryFeedback(.impact(flexibility: .solid), trigger: room.volume)

                        }
                        .onChange(of: room.volume, initial: false) {
                            if isEditingRoomVolume {
                                Task {
                                    await sonosService.setDeviceVolume(ip: room.ip, volume: Int(room.volume))
                                    await sonosService.snapShotGroup(ip: group.coordinatorRoom.ip)
                                }
                            }
                        }
                        .animation(.snappy, value: room.volume)
                        .sensoryFeedback(.impact(flexibility: .solid), trigger: room.volume)
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
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.thickMaterial)
                            .bold()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 20)
                }
            }
        }
        .padding([.leading, .trailing])
        .toolbar(.hidden, for: .navigationBar)
        .toolbarTitleDisplayMode(.inline)
        .containerBackground(.accent.gradient, for: .navigation)
    }
}

#Preview {
    GroupVolumeControlScreen(group: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "", name: "Kitchen")]))
        .environment(SonosService())

}

