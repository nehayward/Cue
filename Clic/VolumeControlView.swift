import SwiftUI
import SonosKit
import VibesDS

struct VolumeControlView: View {
    @Environment(SonosService.self) private var sonosService: SonosService
    @Binding var group: GroupRoom
    @State private var isEditing: Bool = false
    @State private var volumeTask: Task<Void, Error>?
    private let delayDrag: Bool

    init(group: Binding<GroupRoom>, delayDrag: Bool = false) {
        self._group = group
        self.delayDrag = delayDrag
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                Task {
                    await sonosService.setGroupMute(group: group, mute: !group.isMuted)
                }
            } label: {
                Image(group.isMuted ? "speaker.wave.3.slash.fill" : "speaker.wave.3.fill", variableValue: group.groupVolume/100)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(group.isMuted ? .hierarchical : .monochrome)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(.primary)
                    .frame(width: UIDevice.current.userInterfaceIdiom == .phone ? 18 : 24, height: UIDevice.current.userInterfaceIdiom == .phone ? 18 : 24, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .padding(.trailing)
            .hoverEffect(.automatic)

            VibeSlider(value: $group.groupVolume, baseHeight: UIDevice.current.userInterfaceIdiom == .phone ? 12 : 20, delayDrag: delayDrag) { isEditing in
                if group.isMuted {
                    Task {
                        await sonosService.setGroupMute(group: group, mute: false)
                    }
                }
                
                self.isEditing = isEditing
                updateVolume(volume: group.groupVolume)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
                    group.isEditingVolume = isEditing
                }
            }
            .foregroundStyle(.accent)
            Text("\(group.groupVolume, specifier: "%03.0f")%")
                .contentTransition(.numericText())
                .monospacedDigit()
                .animation(.spring.speed(2), value: group.groupVolume)
                .frame(width: 38, alignment: .trailing)
                .fontDesign(.rounded)
                .bold()
        }
        .font(.caption)
        .fontDesign(.rounded)
        .animation(.interactiveSpring, value: group.groupVolume)
        .frame(height: UIDevice.current.userInterfaceIdiom == .phone ? 32 : 40)
        .opacity(group.isMuted ? 0.6 : 1)
        .animation(.spring, value: group.isMuted)
        .tint(.primary)
    }

    private func updateVolume(volume: Double) {
        volumeTask?.cancel()
        volumeTask = Task {
            try Task.checkCancellation()
            await sonosService.setGroupVolume(ip: group.coordinatorRoom.ip, volume: Int(volume))
            if volume.isZero {
                try? await Task.sleep(for: .milliseconds(200))
                await sonosService.snapShotGroup(ip: group.coordinatorRoom.ip)
            }
        }
    }
}

#Preview {
    VolumeControlView(group: .constant(.gym))
        .withEnvironments()
}
