import UIKit
import SwiftUI
import SonosKit
import VibesDS

struct RoomVolumeView: View {
    @Environment(SonosService.self) private var sonosService: SonosService

    @Binding var room: Room
    @State private var isEditing: Bool = false
    @State private var volumeTask: Task<Void, Error>?
    var updatedVolume: (() -> Void)? = nil

    private let touchDelay: TimeInterval

    init(room: Binding<Room>, touchDelay: TimeInterval = 0, updatedVolume: (() -> Void)? = nil) {
        self._room = room
        self.touchDelay = touchDelay
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
                Image(systemName: room.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: room.volume/100)
                    .renderingMode(.template)
                    .contentTransition(.symbolEffect(.automatic))
                    .padding(.trailing, 8)
            }
            .frame(width: 24, alignment: .leading)
            .buttonStyle(.plain)

            VibeSlider(value: $room.volume, touchDelay: touchDelay) { isEditing in
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
        }
        .font(.caption)
        .fontDesign(.rounded)
        .animation(.interactiveSpring, value: room.volume)
    }

    private func updateVolume(volume: Double) {
        volumeTask?.cancel()
        volumeTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            try Task.checkCancellation()
            await sonosService.setDeviceVolume(ip: room.ip, volume: Int(volume))
            updatedVolume?()
        }
    }

}

#Preview {
    return RoomVolumeView(room: .constant(.garage))
        .environment(SonosService())
        .onAppear {
            let thumbImage = UIImage()
            UISlider.appearance().setThumbImage(thumbImage, for: .normal)
        }
}
