import SwiftUI
import SonosKit

struct ContentView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var selected: String?

    var body: some View {
        NavigationSplitView {
            List (sonosService.groups, selection: $selected) { group in
                Section {
                    HStack(alignment: .top) {
                        ArtworkView(group: group)
                            .frame(width: 72, height: 72)
                        ZoneView(group: group)
                        Spacer()
                        MediaControlsView(group: group)
                    }
                    VolumeControlView(roomGroup: group)
                } header: {
                    HStack {
                        Image(systemName: "hifispeaker")
                        Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
                    }
                    .fontDesign(.rounded)
                    .font(.body)
                }
                .tag(group.coordinatorID)
                .headerProminence(.increased)
                .listRowSeparator(.visible, edges: .all)
//                .listRowInsets(EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2))
            }

            //                VStack {
            //                    SceneView(show: $isShowing)
            //                    //                    .listRowBackground(Color.clear)
            //                    Slider(value: .constant(0))
            //                }
            //                .backgroundStyle(.thinMaterial)
        } detail: {
            if selected != nil, let group = sonosService.groups.first(where: { group in
                group.coordinatorID == selected! }) {
                LargePlayerView(group: group)
            }
        }
        .onChange(of: selected) {
            guard let selected else { return }
            let selectedGroup = sonosService.groups.first(where: { room in
                room.coordinatorID == selected
            })

            guard let selectedGroup else { return }
            sonosService.selectedGroup = selectedGroup
        }
        .overlay {
            if sonosService.groups.isEmpty {
                Rectangle()
                    .ignoresSafeArea()
                    .foregroundStyle(.ultraThinMaterial)
                    .overlay {
                        Text("Searching...")
                            .animation(nil)
                    }
                    .transition(.opacity)
            }
        }
    }
}

#Preview {
    ContentView(selected: .constant(nil))
        .environment(SonosService())
}

