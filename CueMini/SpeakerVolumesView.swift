import SwiftUI
import SonosKitMini

struct SpeakerVolumesView: View {
    let device: SonosDevice
    @State private var sonosService = SonosMiniService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(device.allDevices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, id: \.id) { speaker in
                SpeakerVolumeRow(
                    speakerID: speaker.id,
                    speakerIP: speaker.ip,
                    speakerName: speaker.name,
                    coordinatorIP: device.ip
                )
            }
        }
        .fontDesign(.rounded)
        .task {
            await sonosService.updateRoomVolumes(incomingDevices: device.allDevices)
        }
    }
}

// MARK: - Speaker volume row

struct SpeakerVolumeRow: View {
    let speakerID: String
    let speakerIP: String
    let speakerName: String
    let coordinatorIP: String

    @State private var sonosService = SonosMiniService.shared
    @State private var volumeDouble: Double = 0
    @State private var isEditing = false
    @State private var suppressUpdates = false
    @State private var volumeTask: Task<Void, Error>?

    private var volume: Int {
        sonosService.speaker(for: speakerID)?.volume ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(speakerName)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 0) {
                volumeButton(systemName: "minus", delta: -2)

                VibeMiniSlider(value: $volumeDouble, baseHeight: 16, showValue: true) { editing in
                    isEditing = editing
                    if !editing {
                        suppressUpdates = true
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            suppressUpdates = false
                        }
                    }
                    updateVolume()
                }
                .foregroundStyle(.primary)

                volumeButton(systemName: "plus", delta: 2)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.quaternary, in: .rect(cornerRadius: 8))
        .fontDesign(.rounded)
        .onAppear { volumeDouble = Double(volume) }
        .onChange(of: volume) { _, new in
            if !isEditing, !suppressUpdates { volumeDouble = Double(new) }
        }
        .onDisappear { volumeTask?.cancel() }
    }

    private func volumeButton(systemName: String, delta: Int) -> some View {
        Button {
            Task {
                if delta > 0, sonosService.speaker(for: speakerID)?.isMuted ?? false {
                    await SonosMiniService.shared.setRoomMute(IP: speakerIP, mute: false)
                    sonosService.updateSpeakerMute(id: speakerID, muted: false)
                }
                await SonosMiniService.shared.setRelativeVolume(ip: speakerIP, volume: delta)
                volumeDouble = min(100, max(0, volumeDouble + Double(delta)))
                sonosService.updateSpeakerVolume(id: speakerID, volume: Int(volumeDouble))
                await snapshotGroup()
            }
        } label: {
            Image(systemName: systemName)
                .font(.caption.bold())
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
    }

    private func updateVolume() {
        sonosService.updateSpeakerVolume(id: speakerID, volume: Int(volumeDouble))
        volumeTask?.cancel()
        volumeTask = Task {
            try Task.checkCancellation()
            await SonosMiniService.shared.setDeviceVolume(ip: speakerIP, volume: Int(volumeDouble))
            await snapshotGroup()
        }
    }

    private func snapshotGroup() async {
        try? await Task.sleep(for: .milliseconds(400), tolerance: .milliseconds(100))
        await SonosMiniService.shared.snapShotGroup(ip: coordinatorIP)
    }
}
