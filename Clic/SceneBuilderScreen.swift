import CloudStorage
import Combine
import SwiftUI
import SonosKit

struct SceneBuilderScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    @State var selections = Set<String>()
    @State var sceneName: String = ""
    @State var rooms: [Room] = []

    @CloudStorage("com.clic.scenes")
    var scenes: [SonosScene] = []

    var body: some View {
        @Bindable var sonosService = sonosService

        NavigationStack {
            List {
                ForEach($rooms) { $room in
                    Section {
                        Button {
                            if selections.contains(room.id) {
                                selections.remove(room.id)
                            } else {
                                selections.insert(room.id)
                            }
                        } label: {
                            VStack {
                                HStack {
                                    VStack(alignment: .leading) {
                                        HStack {
                                            Text(room.name)
                                            Spacer()
                                            Text(room.volume, format: .number)
                                                .frame(minWidth: 20, alignment: .leading)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: selections.contains(room.id) ? "checkmark.circle.fill" : "checkmark.circle")
                                        .contentTransition(.symbolEffect(.automatic))
                                }
                                Divider()
                                HStack(alignment: .center) {
                                    Image(systemName: "speaker.wave.3.fill", variableValue: room.volume/100)
                                    Slider(value: $room.volume, in: 0...100, step: 2)
                                }
                            }
                        }
                        .buttonStyle(.haptic)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    VStack(alignment: .leading) {
                        Text("Scene")
                        Text("Group and set volume")
                            .foregroundStyle(.secondary)
                    }
                    .fontDesign(.rounded)
                    .bold()
                }
            }
//  MARK: Add Volume Only
//            .safeAreaInset(edge: .bottom) {
//                Toggle(isOn: .constant(true)) {
//                    Text("Set Volume Only")
//                }
//                .toggleStyle(.button)
//                .frame(maxWidth: .infinity, alignment: .trailing)
//                .padding()
//            }
            .safeAreaInset(edge: .bottom) {
                VStack {
                    TextField("Scene Name", text: $sceneName)
                        .textFieldStyle(.roundedBorder)
                        .padding()
                    Button {
                        let rooms = rooms.filter { room in
                            selections.contains(room.id)
                        }
                        let sceneRooms = rooms.map { SceneRoom(id: $0.id, ip: $0.ip, name: $0.name, volume: $0.volume) }
                        let newScene = SonosScene(name: sceneName, rooms: sceneRooms)
                        scenes.append(newScene)
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
                }
                .background {
                    RoundedRectangle(cornerRadius: 20)
                        .foregroundStyle(.ultraThinMaterial)
                        .edgesIgnoringSafeArea(.bottom)
                        .shadow(radius: 2)
                }
            }
        }
        .listSectionSpacing(10)
        .task {
            if sonosService.sortedRooms.isEmpty {
                try? await sonosService.load(useCache: true)
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
        .presentationBackground(.ultraThinMaterial)
        .presentationDetents([.medium, .large])
        .onChange(of: selections) { oldValue, newValue in
            let rooms = rooms.filter { room in
                selections.contains(room.id)
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
