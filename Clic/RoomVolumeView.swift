import UIKit
import SwiftUI
import SonosKit
import VibesDS

struct RoomVolumeView: View {
    @Environment(SonosService.self) private var sonosService: SonosService
    
    @Binding var room: Room
    @State private var volumeTask: Task<Void, Error>?
    @State private var isEditingRoomVolume = false
    var updatedVolume: (() -> Void)? = nil

    private let touchDelay: TimeInterval

    init(room: Binding<Room>, touchDelay: TimeInterval = 0, updatedVolume: (() -> Void)? = nil) {
        self._room = room
        self.touchDelay = touchDelay
        self.updatedVolume = updatedVolume
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Image(systemName: "speaker.wave.3.fill", variableValue: room.volume/100)
                .renderingMode(.template)
                .padding(.trailing, 8)
            VibeSlider(value: $room.volume, in: 0...100, touchDelay: touchDelay) { isEditing in
                self.isEditingRoomVolume = isEditing
                room.isEditingVolume = isEditing
                if !isEditing {
                    let volume = room.volume
                    updateVolume(volume: volume)
                }
            }
            .frame(height: 32)
            Text("\(room.volume, specifier: "%03.0f")%")
                .contentTransition(.numericText())
                .monospacedDigit()
                .animation(.spring.speed(2), value: room.volume)
                .frame(width: 36, alignment: .trailing)
                .fontDesign(.rounded)
        }
        .font(.caption)
        .fontDesign(.rounded)
        .animation(.interactiveSpring, value: room.volume)
    }

    private func updateVolume(volume: Double) {
        volumeTask?.cancel()
        volumeTask = Task {
            room.volume = volume
            try? await Task.sleep(for: .milliseconds(100))
            try Task.checkCancellation()
            room.volume = volume
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
