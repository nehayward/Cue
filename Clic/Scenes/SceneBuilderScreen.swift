import Analytics
import CloudStorage
import Combine
import SwiftUI
import SonosKit
import VibesDS

struct SceneBuilderScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    var group: Binding<GroupRoom>? = nil
    @State var selections = Set<String>()
    @State var sceneName: String = ""
    @State var rooms: [Room] = []
    @State var router = Router()

    @State private var contentToAdd: ContentToAdd = ContentToAdd(add: true)

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some View {
        List {
            //                // TODO: Scenes
            //                if let content = contentToAdd.content {
            //                    PlayableContentView(item: content)
            //                }
            ForEach($rooms) { $room in
                VStack(spacing: 0) {
                    Button {
                        HapticManager.shared.fireHaptic(.selection)
                        if selections.contains(room.id) {
                            selections.remove(room.id)
                        } else {
                            selections.insert(room.id)
                        }
                        let rooms = rooms.filter { room in
                            selections.contains(room.id)
                        }
                        sceneName = rooms.map(\.name).joined(separator: " + ")
                    } label: {
                        HStack {
                            Text(room.name)
                                .font(.title3)
                                .bold()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: selections.contains(room.id) ? "checkmark.circle.fill" : "circle")
                                .symbolEffect(.bounce, options: .speed(3), value: selections.contains(room.id))
                                .font(.title2)
                                .opacity(isSelected(room) ? 1 : 0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.primary)
                        .fontDesign(.rounded)
                        .padding()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    RoomVolumeView(room: $room, delayDrag: true)
                        .foregroundStyle(.primary)
                }
                .listRowBackground(selections.contains(room.id) ? RoundedRectangle(cornerRadius: 12)
                    .foregroundStyle(.placeholder)
                : nil)
                .listRowInsets(EdgeInsets())
            }

//            // TODO: Scenes
//            if let content = contentToAdd.content {
//                Text(content.title)
//            } else {
//                Button {
//                    router.presentedSheet = .sceneSearchAdd(adding: contentToAdd)
//                } label: {
//                    Text("Play your Favorite Song")
//                }
//            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text("Scene")
                    Text("Group and set volume")
                        .foregroundStyle(.secondary)
                }
                .fontDesign(.rounded)
                .bold()
                .padding(.vertical)
            }
        }
//        //  MARK: Add Volume Only
//        .safeAreaInset(edge: .bottom) {
//            Toggle(isOn: .constant(true)) {
//                Text("Set Volume Only Don't Group")
//            }
//            .frame(maxWidth: .infinity, alignment: .trailing)
//            .padding()
//        }
        .safeAreaInset(edge: .bottom) {
            VStack {
                TextField("Scene Name", text: $sceneName)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .backgroundStyle(.thickMaterial)
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    let rooms = rooms.filter { room in
                        selections.contains(room.id)
                    }
                    let sceneRooms = rooms.map { SceneRoom(id: $0.id, ip: $0.ip, name: $0.name, volume: $0.volume) }
                    let newScene = SonosScene(name: sceneName, rooms: sceneRooms, playableContent: contentToAdd.content)
                    scenes.append(newScene)
                    Analytics.shared.track(.createdScene)
                    dismiss()
                } label: {
                    Text("Create Scene")
                        .foregroundStyle(.ultraThickMaterial)
                        .frame(maxWidth: .infinity)
                        .fontWeight(.bold)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom)
                .buttonBorderShape(.capsule)
                .disabled(selections.isEmpty)
            }
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .foregroundStyle(.ultraThinMaterial)
                    .edgesIgnoringSafeArea(.bottom)
                    .shadow(radius: 2)
            }
        }
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .listRowSpacing(10)
        .task {
            if sonosService.sortedRooms.isEmpty {
                try? await sonosService.load(useCache: true)
            }
            rooms = sonosService.sortedRooms.filter {
                $0.state == .active
            }.map {
                let room = Room(id: $0.id, ip: $0.ip, name: $0.name, channelMap: $0.channelMap)
                room.volume = $0.volume
                return room
            }

            let rooms = rooms.filter { room in
                selections.contains(room.id)
            }

            sceneName = rooms.map(\.name).joined(separator: " + ")
        }
        .onAppear {
            Analytics.shared.track(.viewedSceneBuilderScreen)
        }
    }
    
    func isSelected(_ room: Room) -> Bool {
        selections.contains(room.id)
    }
}

#Preview {
    Text("SceneBuilder")
        .sheet(isPresented: .constant(true)) {
            NavigationStack {
                SceneBuilderScreen()
            }
        }
        .environment(SonosService())
}
