import SwiftUI
import SonosKit

struct VolumeControlsScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    var groupID: String
    
    @State var isEditingGroupVolume = false
    @State var isEditingRoomVolume = false
    
    @State private var updateRoomVolumeTask: Task<Void, Error>?
    @State private var volumeTask: Task<Void, Error>?
    @State private var lastSentVolume: Int?

    @State private var subHeight: CGFloat = 0

    var body: some View {
        @Bindable var sonosService = sonosService
        
        ScrollView {
            VStack {
                if let groupIndex = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }){
                    ForEach(sonosService.sorted[groupIndex].rooms.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { room in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(room.name)
                                .fontWeight(.semibold)
                                .fontDesign(.rounded)
                                .padding(.leading)
                            RoomVolumeView(room: room) {
                                volumeTask?.cancel()
                                volumeTask = Task {
                                    sonosService.sorted[groupIndex].isEditingVolume = true
                                    if let volume = try? await sonosService.getGroupVolume(ip: sonosService.sorted[groupIndex].ip), volume != sonosService.sorted[groupIndex].groupVolume {
                                        sonosService.sorted[groupIndex].groupVolume = volume
                                    }
                                    try? await Task.sleep(for: .milliseconds(400), tolerance: .milliseconds(100))
                                    await sonosService.snapShotGroup(ip: sonosService.sorted[groupIndex].coordinatorRoom.ip)
                                    sonosService.sorted[groupIndex].isEditingVolume = false
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .padding([.top, .horizontal])
        .safeArea(edge: .bottom) {
            if let groupIndex = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }){
                Button {
                    syncVolumes()
                } label: {
                    VStack {
                        Text("Sync")
                            .fontWeight(.semibold)
                        Text("Set all to \(Int(sonosService.sorted[groupIndex].groupVolume))")
                            .font(.caption.smallCaps())
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                            .fontDesign(.rounded)
                            .bold()
                    }
                }
                .glassButton()
                .padding([.horizontal, .bottom])
            }
        }
    }
    
    private func syncVolumes() {
        if let groupIndex = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }){
            let group = sonosService.sorted[groupIndex]
            for room in group.rooms {
                Task {
                    await sonosService.setDeviceVolume(ip: room.ip, volume: Int(group.groupVolume))
                }
            }
            Task {
                try await Task.sleep(for: .seconds(1))
                await sonosService.snapShotGroup(ip: group.coordinatorRoom.ip)
            }
        }
    }
}

#Preview {
    Text("Group")
        .sheet(isPresented: .constant(true)) {
            VolumeControlsScreen(groupID: GroupRoom.garagePlusTheater.coordinatorID)
                .environment(SonosService.shared)
                .environment(SelectedGroupService(group: .garagePlusTheater))
        }
}
