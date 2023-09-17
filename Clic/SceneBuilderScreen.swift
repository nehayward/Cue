import CloudStorage
import SwiftUI
import SonosKit

struct SceneBuilderScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    @State var multiSelection = Set<String>()
    @State var sceneName: String = ""
    @State var rooms: [Room] = []

    @CloudStorage("com.clic.scenes")
    var scenes: [SonosScene] = []

    var body: some View {
        @Bindable var sonosService = sonosService

        List(selection: $multiSelection) {
            ForEach($rooms) { $room in
                VStack(alignment: .leading) {
                    Text(room.name)
                    HStack(alignment: .center) {
                        Image(systemName: "speaker.wave.3.fill", variableValue: room.volume/100)
                        Slider(value: $room.volume, in: 0...100, step: 2)
                        Text(room.volume, format: .number)
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            VStack {
                TextField("", text: $sceneName)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                Button {
                    let rooms = rooms.filter { room in
                        multiSelection.contains(room.id)
                    }
                    let sceneRooms = rooms.map { SceneRoom(id: $0.id, ip: $0.ip, name: $0.name, volume: $0.volume) }
                    let newScene = SonosScene(name: sceneName, rooms: sceneRooms)
                    scenes.insert(newScene, at: 0)
//                    print(newScene.name)
//                    print(rooms)
                    //                Task {
                    //                    dismiss()
                    ////                    await sonosService.group(rooms: rooms, to: roomGroup.coordinatorID)
                    //                }
                } label: {
                    Text("Create Scene")
                        .fontWeight(.bold)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background {
                Rectangle()
                    .foregroundStyle(.ultraThinMaterial)
                    .edgesIgnoringSafeArea(.bottom)
                    .shadow(radius: 2)
            }
        }
        .environment(\.editMode, .constant(EditMode.active))
        .task {
            if sonosService.sortedRooms.isEmpty {
                try? await sonosService.load()
                rooms = sonosService.sortedRooms.map {
                    let room = Room(id: $0.id, ip: $0.ip, name: $0.name)
                    room.volume = $0.volume
                    return room
                }
            } else {
                rooms = sonosService.sortedRooms.map {
                    let room = Room(id: $0.id, ip: $0.ip, name: $0.name)
                    room.volume = $0.volume
                    return room
                }
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationDetents([.medium, .large])
        .onChange(of: multiSelection) { oldValue, newValue in
            let rooms = rooms.filter { room in
                multiSelection.contains(room.id)
            }

            sceneName = rooms.map(\.name).joined(separator: " + ")
        }
        .task {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else { return }
            sonosService.monitor()
        }

    }
}

#Preview {
//    @State var sonosService = SonosService()
    Text("HERE")
        .sheet(isPresented: .constant(true)) {
            SceneBuilderScreen()
                .environment(SonosService())

        }
}
