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
        HStack(alignment: .center, spacing: 0) {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                Task {
                    await sonosService.setRoomMute(room: room, mute: !room.isMuted)
                }
            } label: {
                Image(room.isMuted ? "speaker.wave.3.slash.fill" : "speaker.wave.3.fill", variableValue: room.volume/100)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(room.isMuted ? .hierarchical : .monochrome)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(.primary)
                    .frame(width: UIDevice.current.userInterfaceIdiom == .phone ? 18 : 24, height: UIDevice.current.userInterfaceIdiom == .phone ? 18 : 24, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .padding(.trailing)


            VibeSlider(value: $room.volume, baseHeight: UIDevice.current.userInterfaceIdiom == .phone ? 12 : 20, delayDrag: true) { isEditing in
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
            Text("\(room.volume, specifier: "%03.0f")%")
                .contentTransition(.numericText())
                .monospacedDigit()
                .animation(.spring.speed(2), value: room.volume)
                .frame(width: 38, alignment: .trailing)
                .fontDesign(.rounded)
                .bold()
        }
        .opacity(room.isMuted ? 0.4 : 1)
        .font(.caption)
        .fontDesign(.rounded)
        .animation(.interactiveSpring, value: room.volume)
        .animation(.interactiveSpring, value: room.isMuted)
        .frame(height: 40)
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
    return RoomVolumeView(room: .constant(.garage))
        .environment(SonosService.shared)
}
