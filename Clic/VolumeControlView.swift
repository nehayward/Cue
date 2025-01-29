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
                Task {
                    HapticManager.shared.fireHaptic(.selection)
                    await sonosService.setRelativeGroupVolume(ip: group.ip, volume: -2)
                    group.groupVolume = max(0, group.groupVolume - 2)
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
                        group.isEditingVolume = isEditing
                    }
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 24)
                    .bold()
            }
            .tint(.primary)
            .buttonStyle(.liveActivity)
            .buttonRepeatBehavior(.enabled)

            
            VibeSlider(value: $group.groupVolume, baseHeight: UIDevice.current.userInterfaceIdiom == .phone ? 20 : 24, delayDrag: delayDrag, showValue: true) { isEditing in
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
            .foregroundStyle(.primary)
            
            Button {
                if group.isMuted {
                    Task {
                        await sonosService.setGroupMute(group: group, mute: false)
                    }
                }
                Task {
                    HapticManager.shared.fireHaptic(.selection)
                    await sonosService.setRelativeGroupVolume(ip: group.ip, volume: 2)
                    group.groupVolume = min(100, group.groupVolume + 2)
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
                        group.isEditingVolume = isEditing
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
                    .bold()
            }
            .tint(.primary)
            .buttonStyle(.liveActivity)
            .buttonRepeatBehavior(.enabled)
        }
        .font(.caption)
        .fontDesign(.rounded)
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
