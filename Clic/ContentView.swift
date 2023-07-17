import SwiftUI
import SonosKit

struct ContentView: View {
    @Environment(SonosService.self) var sonosService: SonosService

    @State var group: GroupRoom? = nil
    @Binding var selected: String?
    @State var isEditing = false
    @State var grouping = false
    @State var isShowing = false

    @State var multiSelection = Set<String>()
    @Namespace var namespace

    
    var body: some View {
            NavigationSplitView {
                List (sonosService.groups, selection: $selected) { group in
                    Section {
                        HStack {
                            ArtworkView(group: group)
                                .frame(width: 72, height: 72)
                            ZoneView(roomGroup: group)
                        }
                        .overlay {
                            NavigationLink(value:  group,
                                           label: { EmptyView() })
                            .opacity(0)
                        }
                    }
                    .tag(group.coordinatorID)
                }
//                VStack {
//                    SceneView(show: $isShowing)
//                    //                    .listRowBackground(Color.clear)
//                    Slider(value: .constant(0))
//                }
//                .backgroundStyle(.thinMaterial)

//                    .listRowInsets(EdgeInsets())
            } detail: {
                if selected != nil {
                    LargePlayerView(group: sonosService.groups.first(where: { group in
                        group.coordinatorID == selected!
                    })!)
                    .environment(sonosService)
                }
            }
//            .onChange(of: sonosService.groups) {
//                Task {
//                    try await Task.sleep(for: .seconds(1))
//                    selected = sonosService.groups.first(where: { room in
//                        room.coordinatorRoom.isPlaying
//                    })?.coordinatorID
//                }
//            }
//            .onChange(of: selected) {
//                guard let selected else { return }
//                let selectedGroup = sonosService.groups.first(where: { room in
//                    room.coordinatorID == selected
//                })
//
//                guard let selectedGroup else { return }
//                sonosService.selectedGroup = selectedGroup
//            }
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
            .background(Color.clear)

        .safeAreaPadding(.bottom, 140)
        .listSectionSpacing(10)
    }
}

#Preview {
    NavigationStack {
        ContentView(selected: .constant(nil))
            .environment(SonosService())
    }
}

