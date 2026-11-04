import SwiftUI
import SonosKitMini

/// The group's volume: a slim slider, as the system's are in the menu bar, its
/// level beside it.
struct VolumeControlView: View {
    @Binding var device: SonosDevice

    @State private var isEditing: Bool = false
    @State private var volumeTask: Task<Void, Error>?

    var body: some View {
        HStack(spacing: 8) {
            VibeMiniSlider(value: $device.groupVolume, baseHeight: 10) { isEditing in
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

            Text("\(Int(device.groupVolume))")
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)
                .frame(minWidth: 24, alignment: .trailing)
        }
        .opacity(device.isMuted ?? false ? 0.6 : 1)
        .animation(.spring, value: device.isMuted)
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
