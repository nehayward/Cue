import SwiftUI
import SonosKit

struct VolumeControlView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    var roomGroup: GroupRoom
    @State private var isEditing: Bool = false
    @State private var volume: Double = 50

    var body: some View {
//        HStack(alignment: .center) {
//            Image(systemName: "speaker.wave.3.fill", variableValue: roomGroup.coordinatorRoom.volume/100)
            Gauge(
                value: volume,
                in: 0...100,
                label: {
                    Text("\(volume, specifier: "%0.f")")
                        .foregroundStyle(.tint, .thickMaterial)
                        .contentTransition(.symbolEffect(.automatic))
                        .rotationEffect(.degrees(90))
                },
                currentValueLabel: {

                }
            )
            .foregroundStyle(.thinMaterial)
            .gaugeStyle(.accessoryLinearCapacity)
            .rotationEffect(.degrees(-90))
//            .minimumScaleFactor(0.8)
        
//        }
        .onAppear {
//            volume = roomGroup.coordinatorRoom.volume
        }
        .onChange(of: roomGroup.coordinatorRoom.volume) { oldValue, newValue in
            guard !isEditing else { return }
//            withAnimation {
//                volume = newValue
//            }
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
