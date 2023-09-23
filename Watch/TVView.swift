import SwiftUI
import SonosKit

struct TVView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom
    @State var volume: Double = 0
    @State private var volumeTask: Task<Void, Error>?

    var body: some View {
        VStack(alignment: .center) {
            Text("Multichannel PCM 5.1")
            Text(group.groupVolume, format: .number)
            HStack {
                Button {

                } label: {
                    Image(systemName: "moon.zzz")
                        .symbolVariant(.fill)
                }
                .buttonBorderShape(.circle)
                .buttonStyle(.bordered)
                Button {

                } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                }
                .buttonBorderShape(.circle)
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .onAppear {
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                sonosService.monitor()
            }
        }
        .tag(group.coordinatorID)
        .digitalCrownRotation(detent: $group.groupVolume,
                              from: 0,
                              through: 100,
                              by: 2,
                              sensitivity: .low,
                              isContinuous: false,
                              isHapticFeedbackEnabled: true,
                              onChange: { crownEvent in
            volume = group.groupVolume
        })
        .onChange(of: volume) {
            volumeTask?.cancel()
            volumeTask = Task {
                await sonosService.setGroupVolume(ip: group.coordinatorRoom.ip, volume: Int(volume))
            }
        }
        .navigationTitle(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
        .task {
            print("Set Volume")
            volume = group.groupVolume
        }
    }
}

#Preview {
    NavigationStack {
        TVView(group: .constant(.garage))
            .environment(SonosService())
    }
    .listStyle(.carousel)
}

