import SwiftUI
import SonosKitMini

// MARK: Migrate to updated Volume View
struct VolumeControlView: View {
    var device: SonosDevice
    
    @State private var isEditing: Bool = false
    @State private var volumeTask: Task<Void, Error>?
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                Task {
                    await SonosMiniService.shared.setRelativeGroupVolume(ip: device.ip, volume: -2)
//                    group.groupVolume = max(0, group.groupVolume - 2)
//                    Task { [weak self]
//                        try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
//                        group.isEditingVolume = isEditing
//                    }
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 24)
                    .bold()
            }
            .tint(.primary)
            .buttonRepeatBehavior(.enabled)
            
//            VibeSlider(value: .constant(device.groupVolume), baseHeight: 24, delayDrag: false, showValue: true) { isEditing in
//                if group.isMuted {
//                    Task {
//                        await SonosService.shared.setGroupMute(group: group, mute: false)
//                    }
//                }
//                
//                self.isEditing = isEditing
//                updateVolume(volume: group.groupVolume)
//                Task { @MainActor in
//                    try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
//                    group.isEditingVolume = isEditing
//                }
//            }
//            .foregroundStyle(.primary)
            
            Button {
                if device.isMuted ?? false {
                    Task {
                        await SonosMiniService.shared.setGroupMute(device: device, mute: false)
                    }
                }
                Task {
                    await SonosMiniService.shared.setRelativeGroupVolume(ip: device.ip, volume: 2)
//                    group.groupVolume = min(100, group.groupVolume + 2)
//                    Task { @MainActor in
//                        try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
//                        group.isEditingVolume = isEditing
//                    }
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
                    .bold()
            }
            .tint(.primary)
//            .buttonStyle(.liveActivity)
            .buttonRepeatBehavior(.enabled)
        }
        .font(.caption)
        .fontDesign(.rounded)
        .frame(height: 40)
        .opacity(device.isMuted ?? false ? 0.6 : 1)
        .animation(.spring, value: device.isMuted)
        .tint(.primary)
    }

//    private func updateVolume(volume: Double) {
//        volumeTask?.cancel()
//        volumeTask = Task {
//            try Task.checkCancellation()
//            await  SonosService.shared.setGroupVolume(ip: group.coordinatorRoom.ip, volume: Int(volume))
//            if volume.isZero {
//                try? await Task.sleep(for: .milliseconds(200))
//                await  SonosService.shared.snapShotGroup(ip: group.coordinatorRoom.ip)
//            }
//        }
//    }
}

//#Preview {
//    VolumeControlView(group: GroupRoom.gym)
//        .withEnvironments()
//}
