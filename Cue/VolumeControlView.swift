import SwiftUI
import SonosKit
import VibesDS

struct VolumeControlView: View {
    @Bindable var group: GroupRoom
    var delayDrag: Bool = false
    @State private var isEditing: Bool = false
    /// The level the drag most recently asked for, not yet sent.
    @State private var pendingVolume: Int?
    /// The one `SetGroupVolume` send loop, while it runs.
    @State private var volumeTask: Task<Void, Never>?
    /// The last level sent during this drag; cleared when the drag ends so a
    /// button press in between can't make the next drag skip a level.
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

            // Called on every drag tick, not only at the start and end.
            VibeSlider(value: $group.groupVolume, baseHeight: sliderHeight, delayDrag: delayDrag, showValue: true) { isEditing in
                if group.isMuted {
                    Task {
                        await SonosService.shared.setGroupMute(group: group, mute: false)
                    }
                    withAnimation {
                        group.isMuted = false
                    }
                }

                updateVolume(volume: group.groupVolume)

                // Only on a change: an `@Observable` write notifies even when
                // the value is the same, so a write per tick re-rendered every
                // view reading `isEditingVolume` as the pointer moved.
                guard self.isEditing != isEditing else { return }
                self.isEditing = isEditing
                if !isEditing, volumeTask == nil { lastSentVolume = nil }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
                    group.isEditingVolume = isEditing
                }
            } onLongPress: {
                toggleMute()
            }
            .accessibilityAction(named: group.isMuted ? "Unmute" : "Mute") {
                toggleMute()
            }
#if targetEnvironment(macCatalyst)
            // The Mac's long press: a right click.
            .contextMenu {
                Button {
                    toggleMute()
                } label: {
                    Label(
                        group.isMuted ? "Unmute" : "Mute",
                        systemImage: group.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
                    )
                }
            }
#endif
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

    /// A long press on the slider: mutes the whole group, or unmutes it.
    /// Sonos's group mute moves every room, so they're shown muted at once
    /// too, and held against the poll until the speakers catch up.
    @MainActor
    private func toggleMute() {
        HapticManager.shared.fireHaptic(.buttonPress)
        let mute = !group.isMuted
        withAnimation {
            group.holdMute(mute)
            for room in group.rooms where room.isMuted != mute {
                room.holdMute(mute)
            }
        }
        Task { await SonosService.shared.setGroupMute(group: group, mute: mute) }
    }

    /// Sends the drag's level to the speaker, at most one request at a time.
    ///
    /// A drag moves a point per tick. Each used to get its own SOAP request —
    /// the cancel meant to coalesce them was a no-op (`try?` swallowed the
    /// `CancellationError`), so dozens queued up on the speaker, which works
    /// through them one by one and fell seconds behind the slider. Now a
    /// request waits for the one before it and then sends whatever level is
    /// latest, skipping everything in between.
    private func updateVolume(volume: Double) {
        let intVolume = Int(volume)
        guard volumeTask != nil || intVolume != lastSentVolume else { return }
        pendingVolume = intVolume
        guard volumeTask == nil else { return }

        let ip = group.coordinatorRoom.ip
        volumeTask = Task {
            while let next = pendingVolume {
                pendingVolume = nil
                guard next != lastSentVolume else { continue }
                lastSentVolume = next
                await SonosService.shared.setGroupVolume(ip: ip, volume: next)
            }
            volumeTask = nil
            let sent = lastSentVolume
            if !isEditing { lastSentVolume = nil }

            if sent == 0 {
                try? await Task.sleep(for: .milliseconds(200))
                guard volumeTask == nil, pendingVolume == nil else { return }
                await SonosService.shared.snapShotGroup(ip: ip)
            }
        }
    }
}

#Preview {
    VolumeControlView(group: GroupRoom.theaterFixed)
}
