import SwiftUI
import SonosKit
import VibesDS

struct VolumeControlView: View {
    @Bindable var group: GroupRoom
    var delayDrag: Bool = false
    @State private var isEditing: Bool = false
    @State private var volumeTask: Task<Void, Error>?
    @State private var lastSentVolume: Int?

    @ScaledMetric(relativeTo: .caption) private var sliderHeight: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 20 : 24

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                Task {
                    HapticManager.shared.fireHaptic(.selection)
                    await SonosService.shared.setRelativeGroupVolume(ip: group.ip, volume: -1)
                    group.groupVolume = max(0, group.groupVolume - 1)
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
            .accessibilityLabel("Volume Down")

            VibeSlider(value: $group.groupVolume, baseHeight: sliderHeight, delayDrag: delayDrag, showValue: true) { isEditing in
                if group.isMuted {
                    Task {
                        await SonosService.shared.setGroupMute(group: group, mute: false)
                    }
                    withAnimation {
                        group.isMuted = false
                    }
                }
                
                self.isEditing = isEditing
                updateVolume(volume: group.groupVolume)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
                    group.isEditingVolume = isEditing
                }
            }
            .accessibilityLabel("Volume")
            .accessibilityValue(group.coordinatorRoom.isOutputFixed ? "Fixed" : "\(Int(group.groupVolume.rounded())) percent\(group.isMuted ? ", muted" : "")")
            .opacity(group.coordinatorRoom.isOutputFixed ? 0 : 1)
            .overlay {
                if group.coordinatorRoom.isOutputFixed {
                    Text("Fixed Volume")
                        .foregroundStyle(.secondary)
                        .bold()
                        .fontDesign(.rounded)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial.opacity(0.6))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(.primary)
            Button {
                if group.isMuted {
                    Task {
                        await SonosService.shared.setGroupMute(group: group, mute: false)
                        withAnimation {
                            group.isMuted = false
                        }
                    }
                }
                Task {
                    HapticManager.shared.fireHaptic(.selection)
                    await SonosService.shared.setRelativeGroupVolume(ip: group.ip, volume: 1)
                    group.groupVolume = min(100, group.groupVolume + 1)
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
            .accessibilityLabel("Volume Up")
        }
        .font(.caption)
        .fontDesign(.rounded)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .opacity(group.isMuted ? 0.6 : 1)
        .animation(.spring, value: group.isMuted)
        .tint(.primary)
        .disabled(group.coordinatorRoom.isOutputFixed)
    }

    private func updateVolume(volume: Double) {
        let intVolume = Int(volume)
        
        guard lastSentVolume != intVolume else { return }
        lastSentVolume = intVolume
        
        volumeTask?.cancel()
        volumeTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            try? Task.checkCancellation()
            await SonosService.shared.setGroupVolume(ip: group.coordinatorRoom.ip, volume: intVolume)
            
            if volume.isZero {
                try? await Task.sleep(for: .milliseconds(200))
                try Task.checkCancellation()
                await SonosService.shared.snapShotGroup(ip: group.coordinatorRoom.ip)
            }
        }
    }
}

#Preview {
    VolumeControlView(group: GroupRoom.theaterFixed)
}
