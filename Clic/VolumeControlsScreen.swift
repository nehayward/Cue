import SwiftUI
import SonosKit

struct VolumeControlsScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    var groupID: String

    @State var isEditingGroupVolume = false
    @State var isEditingRoomVolume = false

    @State private var volumeTask: Task<Void, Error>?
    
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
                    VolumeControlView(group: $sonosService.sorted[groupID], touchDelay: 0.01)
                        .frame(height: 40)
                        .listRowBackground(isMacCatalyst ? Color.clear : nil)
                        .listRowSeparator(.hidden)
                    
                    ForEach($sonosService.sorted[groupID].rooms) { $room in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(room.name)
                                .fontDesign(.rounded)
                            RoomVolumeView(room: $room) {
                                volumeTask?.cancel()
                                volumeTask = Task {
                                    try await Task.sleep(for: .milliseconds(300))
                                    try Task.checkCancellation()
                                    await sonosService.snapShotGroup(ip: sonosService.sorted[groupID].coordinatorRoom.ip)
                                }
                            }
                        }
                        .listRowBackground(isMacCatalyst ? Color.clear : nil)
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
                            Text("Set all to \(sonosService.sorted[groupID].groupVolume, specifier: "%03.0f")%")
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

