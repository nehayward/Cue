import UIKit
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
            .sensoryFeedback(.impact(flexibility: .solid), trigger: volume)
            Text("\(volume, specifier: "%02.0f")%")
                .monospacedDigit()
        }
        .font(.caption)
        .fontDesign(.rounded)
        .onChange(of: roomGroup.groupVolume) {
            guard !isEditing else { return }
            withAnimation {
                volume = roomGroup.groupVolume
            }
        }
        .onChange(of: volume) {
            if isEditing {
                Task {
                    await sonosService.setGroupVolume(ip: roomGroup.coordinatorRoom.ip, volume: Int(volume))
                }
            }
        }
    }
}

#Preview {
    VolumeControlView(roomGroup: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "", name: "Kitchen")]))
        .environment(SonosService())

}
