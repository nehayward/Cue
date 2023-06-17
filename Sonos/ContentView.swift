import SwiftUI
import SonosKit

struct ContentView: View {
    @State var sonosService = SonosService()

    let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                ForEach($sonosService.sonosDevices) { $device in
                    HStack {
                        ArtworkView(device: device)
                        ZoneView(device: $device)
                    }
                    .environment(sonosService)
                    .onChange(of: device.volume) { oldValue, newValue in
                        print(newValue)
                    }

                }
            }
            .task {
                await sonosService.load()
                sonosService.server.start()
            }
            .navigationTitle("Zones")
//            .onReceive(timer) { input in
//                withAnimation(.smooth) {
//                    sonosService.sonosDevices[Int.random(in: 0...sonosService.sonosDevices.count - 1)].volume = Double.random(in: 10...80)
//                }
//            }
        }
    }
}

#Preview {
    ContentView()
}

