import Analytics
import CloudStorage
import Combine
import SwiftUI
import SonosKit
import VibesDS


// TODO: Add edit scene.
struct EditSceneScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    let scene: SonosScene
    @State var selections = Set<String>()
    @State var sceneName: String = ""
    @State var rooms: [Room] = []
    @State var router = Router()

    @State private var contentToAdd: ContentToAdd = ContentToAdd(add: true)

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []
    
    init(scene: SonosScene) {
        self.scene = scene
    }

    var body: some View {
        List {
            //                // TODO: Scenes
            //                if let content = contentToAdd.content {
            //                    PlayableContentView(item: content)
            //                }
            ForEach($rooms) { $room in
                VStack {
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
                            Spacer()
                            Image(systemName: selections.contains(room.id) ? "checkmark.circle.fill" : "checkmark.circle")
                                .symbolEffect(.bounce, options: .speed(5), value: selections.contains(room.id))
                        }
                        .foregroundStyle(selections.contains(room.id) ? .black : .primary)
                        .fontDesign(.rounded)
                        .bold()
                    }
                    RoomVolumeView(room: $room, delayDrag: true)
                        .foregroundStyle(selections.contains(room.id) ? .black : .primary)
                        .tint(selections.contains(room.id) ? .black : .accentColor)
                }
                .listRowBackground(
                    selections.contains(room.id) ? RoundedRectangle(cornerRadius: 12)
                        .foregroundStyle(Color.accentColor.gradient.opacity(0.8))
                    : nil
                )
                .task {
                    for room in scene.rooms {
                        selections.insert(room.id)
                    }
                }
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
}

#Preview {
    Text("SceneBuilder")
        .sheet(isPresented: .constant(true)) {
            NavigationStack {
//                EditSceneScreen(scene: .init(name: "Test", rooms: [SceneRoom]))
            }
        }
        .environment(SonosService())
}
