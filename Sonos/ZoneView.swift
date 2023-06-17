import SwiftUI
import SonosKit

struct ZoneView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var device: SonosDevice
    @State var isPlaying: Bool = false
    @State var url: URL?

    var body: some View {
        let _ = Self._printChanges() // This have been added to code

        VStack(alignment: .leading) {
            HStack {
                VStack(alignment: .listRowSeparatorLeading) {
                    Label(device.name, systemImage: "hifispeaker.fill")
                    Text(device.ipAddress)
                        .textSelection(.enabled)
                }
                Spacer()
                Button(action: {
                    Task {
                        if isPlaying {
                            await sonosService.pause(ip: device.ipAddress)
                        } else {
                            await sonosService.play(ip: device.ipAddress)
                        }
                        isPlaying.toggle()
                    }
                }, label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                })
                .buttonStyle(.borderedProminent)
            }
            .fontDesign(.rounded)
            Slider(value: $device.volume, in: 0...100, step: 5)
                .onChange(of: device.volume) { oldValue, newValue in
                    newValue
                }
        }
        .task {
            let volume = await sonosService.getVolume(ip: device.ipAddress)
            withAnimation {
                device.volume = volume
            }
            let playback = await sonosService.getPlaybackInfo(ip: device.ipAddress)

            if playback == "PLAYING" {
                isPlaying = true
            } else {
                isPlaying = false
            }
        }
    }
}

//#Preview {
//    ZoneView(device: .constant(SonosDevice(name: "Kitchen", ipAddress: "192.168.4.153", volume: 0)))
//        .environment(SonosService())
//}
//
