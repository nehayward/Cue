import SwiftUI
import SonosKit

struct DebugView: View {
    @State var sonosService: SonosService
    @Binding var current: GroupRoom

    var body: some View {

        NavigationSplitView {
            List ($sonosService.groups) { $group in
                Section {
                   DebugEmbedTest(sonosService: sonosService, group: $group)
                    VStack {
                        Text(group.coordinatorRoom.track.name)
                        Text("\(group.coordinatorRoom.isPlaying ? "True" : "False")")
                    }
                } header: {
                    HStack {
                        Image(systemName: "hifispeaker.fill")
                        Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
                    }
                    .fontDesign(.rounded)
                    .font(.body)
                }
                .headerProminence(.increased)
                .tag(group)

            }
//            VStack {
//                SceneView(show: $isShowing)
//                //                    .listRowBackground(Color.clear)
//                Slider(value: .constant(0))
//            }
//            .backgroundStyle(.thinMaterial)
        } detail: {
            Text("HERE")
//            if let current {
//                PlayerView(sonosService: sonosService, group: current)
//            }
        }
    }
}
//
//#Preview {
//    ContentView(current: .garage)
//        .environment(SonosService())
//        .environment(SubscriptionService())
//}
//
