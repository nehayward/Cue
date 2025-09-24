import SwiftUI
import SonosKitMini

// MARK: Migrate to updated Volume View
struct VolumeControlView: View {
    @Binding var device: SonosDevice
    
    @State private var isEditing: Bool = false
    @State private var volumeTask: Task<Void, Error>?
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                Task {
                    await SonosMiniService.shared.setRelativeGroupVolume(ip: device.ip, volume: -2)
                    device.groupVolume = max(0, device.groupVolume - 2)
                    Task {
                        try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
                        device.isEditingVolume = isEditing
                    }
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 24)
                    .bold()
            }
            .tint(.primary)
            .buttonRepeatBehavior(.enabled)
            .buttonBorderShape(.circle)
        
            VibeMiniSlider(value: $device.groupVolume, baseHeight: 24, showValue: true) { isEditing in
                if device.groupIsMuted {
                    Task {
                        await SonosMiniService.shared.setGroupMute(device: device)
                        try? await SonosMiniService.shared.updateWatchDevices(from: [device])
                    }
                }
                
                self.isEditing = isEditing
                updateVolume(volume: device.groupVolume)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
                    device.isEditingVolume = isEditing
                }
            }
            .foregroundStyle(.primary)
            
            Button {
                if device.groupIsMuted {
                    Task {
                        await SonosMiniService.shared.setGroupMute(device: device, mute: false)
                        try? await SonosMiniService.shared.updateWatchDevices(from: [device])
                    }
                }
                Task {
                    await SonosMiniService.shared.setRelativeGroupVolume(ip: device.ip, volume: 2)
                    device.groupVolume = min(100, device.groupVolume + 2)
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
                        device.isEditingVolume = isEditing
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
                    .bold()
            }
            .tint(.primary)
            .buttonRepeatBehavior(.enabled)
            .buttonBorderShape(.circle)
        }
        .font(.caption)
        .fontDesign(.rounded)
        .frame(height: 40)
        .opacity(device.isMuted ?? false ? 0.6 : 1)
        .animation(.spring, value: device.isMuted)
        .tint(.primary)
    }

    private func updateVolume(volume: Double) {
        volumeTask?.cancel()
        volumeTask = Task {
            try Task.checkCancellation()
            await  SonosMiniService.shared.setGroupVolume(ip: device.ip, volume: Int(volume))
            if volume.isZero {
                try? await Task.sleep(for: .milliseconds(200))
                await SonosMiniService.shared.snapShotGroup(ip: device.ip)
            }
        }
    }
}

//#Preview {
//    VolumeControlView(group: GroupRoom.gym)
//        .withEnvironments()
//}
