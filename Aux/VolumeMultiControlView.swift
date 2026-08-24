import SwiftUI
import SonosKit

struct VolumeMultiControlView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Bindable var group: GroupRoom
    @State var isEditingGroupVolume = false
    @State var isEditingRoomVolume = false
    
    @State private var updateRoomVolumeTask: Task<Void, Error>?
    @State private var volumeTask: Task<Void, Error>?
    @State private var lastSentVolume: Int?
    
    @State private var hideTask: Task<Void, Never>?
    @State private var showRoomVolumes: Bool = false

    var body: some View {
        @Bindable var sonosService = sonosService
        VolumeControlView(group: group)
            .overlay(alignment: .top) {
                ScrollView {
                    VStack {
                        ForEach(group.rooms) { room in
                            VStack(alignment: .center, spacing: 0) {
                                Text(room.name)
                                    .fontWeight(.semibold)
                                    .fontDesign(.rounded)
                                VolumeControlRoomView(room: room, delayDrag: false) {
                                    volumeTask?.cancel()
                                    volumeTask = Task {
                                        group.isEditingVolume = true
                                        if let volume = try? await sonosService.getGroupVolume(ip: group.ip), volume != group.groupVolume {
                                            group.groupVolume = volume
                                        }
                                        try? await Task.sleep(for: .milliseconds(400), tolerance: .milliseconds(100))
                                        await sonosService.snapShotGroup(ip: group.ip)
                                        group.isEditingVolume = false
                                    }
                                }
                                .onChange(of: group.groupVolume) {
                                    let intVolume = Int(group.groupVolume)
                                    // Only update if the volume changed
                                    guard lastSentVolume != intVolume else { return }
                                    lastSentVolume = intVolume
                                    
                                    updateRoomVolumeTask?.cancel()
                                    updateRoomVolumeTask = Task {
                                        try? Task.checkCancellation()
                                        await sonosService.updateRoomVolumes(for: group)
                                        try? Task.checkCancellation()
                                        try await Task.sleep(for: .milliseconds(200), tolerance: .milliseconds(100))
                                        await sonosService.updateRoomVolumes(for: group)
                                    }
                                }
                            }
                        }
                        ForEach(group.rooms) { room in
                            VStack(alignment: .center, spacing: 4) {
                                Text(room.name)
                                    .fontDesign(.rounded)
                                VolumeControlRoomView(room: room, delayDrag: false) {
                                    volumeTask?.cancel()
                                    volumeTask = Task {
                                        group.isEditingVolume = true
                                        if let volume = try? await sonosService.getGroupVolume(ip: group.ip), volume != group.groupVolume {
                                            group.groupVolume = volume
                                        }
                                        try? await Task.sleep(for: .milliseconds(400), tolerance: .milliseconds(100))
                                        await sonosService.snapShotGroup(ip: group.ip)
                                        group.isEditingVolume = false
                                    }
                                }
                                .onChange(of: group.groupVolume) {
                                    let intVolume = Int(group.groupVolume)
                                    // Only update if the volume changed
                                    guard lastSentVolume != intVolume else { return }
                                    lastSentVolume = intVolume
                                    
                                    updateRoomVolumeTask?.cancel()
                                    updateRoomVolumeTask = Task {
                                        try? Task.checkCancellation()
                                        await sonosService.updateRoomVolumes(for: group)
                                        try? Task.checkCancellation()
                                        try await Task.sleep(for: .milliseconds(200), tolerance: .milliseconds(100))
                                        await sonosService.updateRoomVolumes(for: group)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(idealHeight: 500)
                .padding()
                .frame(maxWidth: .infinity)
                .scaleEffect(x: 1, y: showRoomVolumes ? 1 : 0, anchor: .bottom)
                .frame(height: showRoomVolumes ? nil : 0, alignment: .bottom)
                .alignmentGuide(.top, computeValue: { d in
                    d[.bottom]
                })
                .onChange(of: group.isEditingVolume) {
                    if group.isEditingVolume {
                        showSlidersAnimated()
                    }
                }
                .background(.thickMaterial, in: .rect)
            }
            .overlay(alignment: .bottom) {
                Button {
                    syncVolumes()
                } label: {
                    Text("Set all to\(group.groupVolume, specifier: "%03.0f")")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                        .fontDesign(.rounded)
                        .bold()
                }
                .buttonBorderShape(.capsule)
                .buttonStyle(.bordered)
                .tint(.accent)
                .opacity(showRoomVolumes ? 1 : 0)
                .alignmentGuide(.bottom, computeValue: { d in
                    d[.top]
                })
            }
    }
    
    private func showSlidersAnimated() {
        withAnimation(.interactiveSpring) { showRoomVolumes = true }
        
        hideTask?.cancel()
        
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                withAnimation(.interactiveSpring) { showRoomVolumes = false }
            }
        }
    }
        
        
    
//ToolbarItemGroup(placement: .bottomBar) {
//    if let groupID = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }){
//        Button {
//            syncVolumes()
//        } label: {
//            Text("Set all to\(sonosService.sorted[groupID].groupVolume, specifier: "%03.0f")%")
//                .monospacedDigit()
//                .frame(maxWidth: .infinity)
//                .padding(.horizontal)
//                .fontDesign(.rounded)
//                .bold()
//        }
//        .buttonBorderShape(.capsule)
//        .buttonStyle(.bordered)
//        .tint(.accent)
//    }
//}
    private func syncVolumes() {
//        if let groupID = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }){
//            let group = sonosService.sorted[groupID]
//            for room in group.rooms {
//                Task {
//                    await sonosService.setDeviceVolume(ip: room.ip, volume: Int(group.groupVolume))
//                }
//            }
//            Task {
//                try await Task.sleep(for: .seconds(1))
//                await sonosService.snapShotGroup(ip: group.coordinatorRoom.ip)
//            }
//        }
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

