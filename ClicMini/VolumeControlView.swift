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
                    try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
                    device.isEditingVolume = isEditing
                }
            } label: {
                Image(systemName: "minus")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .buttonRepeatBehavior(.enabled)

            VibeMiniSlider(value: $device.groupVolume, baseHeight: 24, showValue: true) { isEditing in
                self.isEditing = isEditing
                device.isEditingVolume = true
                Task {
                    if device.groupIsMuted {
                        await SonosMiniService.shared.setGroupMute(device: device)
                        try? await SonosMiniService.shared.updateWatchDevices(from: [device])
                    }

                    updateVolume(volume: device.groupVolume)
                    if !isEditing {
                        try? await Task.sleep(for: .seconds(2))
                        device.isEditingVolume = false
                    }
                }
            }
            .foregroundStyle(.primary)

            Button {
                Task {
                    if device.groupIsMuted {
                        await SonosMiniService.shared.setGroupMute(device: device, mute: false)
                        try? await SonosMiniService.shared.updateWatchDevices(from: [device])
                    }
                    await SonosMiniService.shared.setRelativeGroupVolume(ip: device.ip, volume: 2)
                    device.groupVolume = min(100, device.groupVolume + 2)
                    try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
                    device.isEditingVolume = isEditing
                }
            } label: {
                Image(systemName: "plus")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .buttonRepeatBehavior(.enabled)
        }
        .font(.caption)
        .fontDesign(.rounded)
        .frame(height: 40)
        .opacity(device.isMuted ?? false ? 0.6 : 1)
        .animation(.spring, value: device.isMuted)
        .tint(.primary)
        .onDisappear {
            volumeTask?.cancel()
        }
    }

    private func updateVolume(volume: Double) {
        volumeTask?.cancel()
        volumeTask = Task {
            try Task.checkCancellation()
            await SonosMiniService.shared.setGroupVolume(ip: device.ip, volume: Int(volume))
            if volume.isZero {
                try? await Task.sleep(for: .milliseconds(200))
                await SonosMiniService.shared.snapShotGroup(ip: device.ip)
            }
        }
    }
}
