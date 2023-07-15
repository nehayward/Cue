import SwiftUI
import SonosKit

struct SceneBuilderScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    @State var multiSelection = Set<String>()
    @State var sceneName: String = ""

    var scenes: SonosScene?

    var body: some View {
        @Bindable var sonosService = sonosService

        List(selection: $multiSelection) {
            ForEach($sonosService.rooms) { $room in
//                @Bindable var volume = room.
                VStack(alignment: .leading) {
                    Text(room.name)
                    HStack(alignment: .center) {
                        Image(systemName: "speaker.wave.3.fill", variableValue: room.volume/100)
                        Slider(value: $room.volume , in: 0...100, step: 2) { isEditing in
//                            self.isEditing = isEditing
                        }
                        Text(room.volume, format: .number)
                    }
                }
                .listRowBackground(Color.clear)
            }
            Section {
                TextField("", text: $sceneName)
                    .backgroundStyle(.clear)
            }
        }
        .scrollContentBackground(.hidden)
//        .overlay(alignment: .bottom) {
//            TextField("", text: $sceneName)
//        }
        .overlay(alignment: .bottom) {
            Button {
                let rooms = sonosService.rooms.filter { room in
                    multiSelection.contains(room.id)
                }

                let newScene = SonosScene(name: sceneName, rooms: rooms)
                print(newScene.name)
//                Task {
//                    dismiss()
////                    await sonosService.group(rooms: rooms, to: roomGroup.coordinatorID)
//                }
            } label: {
                Text("Create Scene")
//                    .fontWeight(.bold)
            }
            .buttonStyle(.borderedProminent)
        }
        .environment(\.editMode, .constant(EditMode.active))
        .task {
//            if sonosService.rooms.isEmpty {
//                await sonosService.load()
//            }
        }
        .presentationBackground(.thinMaterial)
        .presentationDetents([.medium, .large])
        .onChange(of: multiSelection) { oldValue, newValue in
            let rooms = sonosService.rooms.filter { room in
                multiSelection.contains(room.id)
            }

            sceneName = rooms.map(\.name).joined(separator: " + ")
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
