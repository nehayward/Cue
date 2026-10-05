import SwiftUI
import SonosKit
import VibesDS

struct RoomVolumeView: View {
    @Environment(SonosService.self) private var sonosService: SonosService

    @Bindable var room: Room
    @State private var isEditing: Bool = false
    @State private var volumeTask: Task<Void, Error>?
    var updatedVolume: (() -> Void)? = nil

    private let delayDrag: Bool

    init(room: Room, delayDrag: Bool = false, updatedVolume: (() -> Void)? = nil) {
        self.room = room
        self.delayDrag = delayDrag
        self.updatedVolume = updatedVolume
    }

    var body: some View {
        VStack {
            HStack(alignment: .center, spacing: 0) {
                Button {
                    Task {
                        HapticManager.shared.fireHaptic(.selection)
                        await sonosService.setRelativeVolume(ip: room.ip, volume: -1)
                        room.volume = max(0, room.volume - 1)
                        updatedVolume?()
                    }
                    
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
                        room.isEditingVolume = isEditing
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
                
                VibeSlider(value: $room.volume, baseHeight: UIDevice.current.userInterfaceIdiom == .phone ? 20 : 24, delayDrag: true, showValue: true) { isEditing in
                    if room.isMuted {
                        Task {
                            await sonosService.setRoomMute(room: room, mute: false)
                        }
                    }
                    self.isEditing = isEditing
                    updateVolume(volume: room.volume)
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
                        room.isEditingVolume = isEditing
                    }
                } onLongPress: {
                    toggleMute()
                }
                .accessibilityAction(named: room.isMuted ? "Unmute" : "Mute") {
                    toggleMute()
                }
#if targetEnvironment(macCatalyst)
                // The Mac's long press: a right click.
                .contextMenu {
                    Button {
                        toggleMute()
                    } label: {
                        Label(
                            room.isMuted ? "Unmute" : "Mute",
                            systemImage: room.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
                        )
                    }
                }
#endif
                .accessibilityLabel("\(room.name) Volume")
                .accessibilityValue("\(Int(room.volume.rounded())) percent\(room.isMuted ? ", muted" : "")")
                
                Button {
                    if room.isMuted {
                        Task {
                            await sonosService.setRoomMute(IP: room.ip, mute: false)
                        }
                    }
                    Task {
                        HapticManager.shared.fireHaptic(.selection)
                        await sonosService.setRelativeVolume(ip: room.ip, volume: 1)
                        room.volume = min(100, room.volume + 1)
                        updatedVolume?()
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
                        room.isEditingVolume = isEditing
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
        }
        .opacity(room.isMuted ? 0.4 : 1)
        .font(.caption)
        .fontDesign(.rounded)
        .animation(.interactiveSpring, value: room.isMuted)
        .frame(height: 48)
    }

    /// A long press on the slider: mutes the room, or unmutes it.
    /// `setRoomMute` shows it at once and holds it against the poll.
    @MainActor
    private func toggleMute() {
        HapticManager.shared.fireHaptic(.buttonPress)
        let mute = !room.isMuted
        Task { await sonosService.setRoomMute(room: room, mute: mute) }
    }

    private func updateVolume(volume: Double) {
        volumeTask?.cancel()
        volumeTask = Task {
            try Task.checkCancellation()
            await sonosService.setDeviceVolume(ip: room.ip, volume: Int(volume))
            updatedVolume?()
        }
    }

}

#Preview {
    RoomVolumeView(room: .gym)
        .environment(SonosService.shared)
}
