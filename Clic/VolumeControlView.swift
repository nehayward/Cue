import SwiftUI
import SonosKit

struct VolumeControlView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    var roomGroup: GroupRoom
    @State private var isEditing: Bool = false
    @State private var volume: Double = 0

    var body: some View {
        HStack(alignment: .center) {
            Image(systemName: "speaker.wave.3.fill", variableValue: roomGroup.coordinatorRoom.volume/100)
            Slider(value: $volume, in: 0...100, step: 2) { isEditing in
                self.isEditing = isEditing
            }
        }
        .onAppear {
            volume = roomGroup.coordinatorRoom.volume
        }
        .onChange(of: roomGroup.coordinatorRoom.volume) { oldValue, newValue in
            guard !isEditing else { return }
            withAnimation {
                volume = newValue
            }
        }
        .onChange(of: volume) { oldValue, newValue in
            if isEditing {
                Task {
                    await sonosService.setDeviceVolume(ip: roomGroup.coordinatorRoom.ip, volume: Int(newValue))
                }
            }
        }
    }
}

#Preview {
    VolumeControlView(roomGroup: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "", name: "Kitchen")]))
        .environment(SonosService())

}
