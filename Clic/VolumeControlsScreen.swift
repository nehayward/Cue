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

    private var isMacCatalyst: Bool {
#if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        @Bindable var sonosService = sonosService
        NavigationStack {
            List {
                if let groupID = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }){
                    if sonosService.sorted[groupID].rooms.count > 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sonosService.sorted[groupID].nameWithCount)
                                .fontDesign(.rounded)
                                .bold()
                                .padding(.leading)
                            VolumeControlView(group: sonosService.sorted[groupID], delayDrag: true)
                                .frame(height: 40)
                                .listRowSeparator(.hidden)
                                .onChange(of: sonosService.sorted[groupID].groupVolume) {
                                    let intVolume = Int(sonosService.sorted[groupID].groupVolume)
                                    // Only update if the volume changed
                                    guard lastSentVolume != intVolume else { return }
                                    lastSentVolume = intVolume

                                    updateRoomVolumeTask?.cancel()
                                    updateRoomVolumeTask = Task {
                                        try? Task.checkCancellation()
                                        await sonosService.updateRoomVolumes(for: sonosService.sorted[groupID])
                                        try? Task.checkCancellation()
                                        try await Task.sleep(for: .milliseconds(200), tolerance: .milliseconds(100))
                                        await sonosService.updateRoomVolumes(for: sonosService.sorted[groupID])
                                    }
                                }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    
                    ForEach($sonosService.sorted[groupID].rooms) { $room in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(room.name)
                                .fontDesign(.rounded)
                                .padding(.leading)
                            RoomVolumeView(room: $room) {
                                volumeTask?.cancel()
                                volumeTask = Task {
                                    sonosService.sorted[groupID].isEditingVolume = true
                                    if let volume = try? await sonosService.getGroupVolume(ip: sonosService.sorted[groupID].ip), volume != sonosService.sorted[groupID].groupVolume {
                                        sonosService.sorted[groupID].groupVolume = volume
                                    }
                                    try? await Task.sleep(for: .milliseconds(400), tolerance: .milliseconds(100))
                                    await sonosService.snapShotGroup(ip: sonosService.sorted[groupID].coordinatorRoom.ip)
                                    sonosService.sorted[groupID].isEditingVolume = false
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .listRowSpacing(-10)
            .navigationTitle("Room Volume Controls")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    if let groupID = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }){
                        Button {
                            syncVolumes()
                        } label: {
                            Text("Set all to\(sonosService.sorted[groupID].groupVolume, specifier: "%03.0f")%")
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal)
                                .fontDesign(.rounded)
                                .bold()
                        }
                        .buttonBorderShape(.capsule)
                        .buttonStyle(.bordered)
                        .tint(.accent)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(24)
    }
    
    private func syncVolumes() {
        if let groupID = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }){
            let group = sonosService.sorted[groupID]
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

