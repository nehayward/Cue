import SwiftUI
import SonosKit
import VibesDS

struct RoomVolumeView: View {
    @Environment(SonosService.self) private var sonosService: SonosService

    @Binding var room: Room
    @State private var isEditing: Bool = false
    @State private var volumeTask: Task<Void, Error>?
    var updatedVolume: (() -> Void)? = nil

    private let delayDrag: Bool

    init(room: Binding<Room>, delayDrag: Bool = false, updatedVolume: (() -> Void)? = nil) {
        self._room = room
        self.delayDrag = delayDrag
        self.updatedVolume = updatedVolume
    }

    var body: some View {
        VStack {
            HStack(alignment: .center, spacing: 0) {
                Button {
                    Task {
                        HapticManager.shared.fireHaptic(.selection)
                        await sonosService.setRelativeVolume(ip: room.ip, volume: -2)
                        room.volume = max(0, room.volume - 2)
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
                }
                
                Button {
                    if room.isMuted {
                        Task {
                            await sonosService.setRoomMute(IP: room.ip, mute: false)
                        }
                    }
                    Task {
                        HapticManager.shared.fireHaptic(.selection)
                        await sonosService.setRelativeVolume(ip: room.ip, volume: 2)
                        room.volume = min(100, room.volume + 2)
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
            }
        }
        .opacity(room.isMuted ? 0.4 : 1)
        .font(.caption)
        .fontDesign(.rounded)
        .animation(.interactiveSpring, value: room.isMuted)
        .frame(height: 48)
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
    RoomVolumeView(room: .constant(.gym))
        .environment(SonosService.shared)
}
