import SwiftUI
import SonosKitMini

struct VolumeMiniView: View {
    @Binding var device: SonosDevice
    @State private var isEditing: Bool = false
    @State private var volumeTask: Task<Void, Error>?

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                Task {
                    await SonosMiniService.shared.setGroupMute(device: device)
                }
            } label: {
                Image(device.groupIsMuted ? "speaker.wave.3.slash.fill" : "speaker.wave.3.fill")
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(device.groupIsMuted ? .hierarchical : .monochrome)
                    .foregroundStyle(.primary)
                    .frame(width: 16, height: 16, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .padding(.trailing)

            VibeMiniSlider(value: $device.groupVolume, baseHeight: 20, delayDrag: false) { isEditing in
                if device.groupIsMuted {
                    Task {
                        await SonosMiniService.shared.setGroupMute(device: device)
                    }
                }
                
                self.isEditing = isEditing
                updateVolume(volume: device.groupVolume)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
                    device.isEditingVolume = isEditing
                }
            }
            .foregroundStyle(.teal)
            Text("\(device.groupVolume, specifier: "%03.0f")%")
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
                .fontDesign(.rounded)
                .bold()
        }
        .font(.caption)
        .fontDesign(.rounded)
        .frame(height: 40)
        .opacity(device.groupIsMuted ? 0.6 : 1)
        .animation(.spring, value: device.groupIsMuted)
        .tint(.primary)
    }

    private func updateVolume(volume: Double) {
        volumeTask?.cancel()
        volumeTask = Task {
            try Task.checkCancellation()
            await SonosMiniService.shared.setGroupVolume(ip: device.ip, volume: Int(volume))
            if volume.isZero {
                try? await Task.sleep(for: .milliseconds(200))
                await SonosMiniService.shared.setGroupMute(device: device)
            }
        }
    }
}
