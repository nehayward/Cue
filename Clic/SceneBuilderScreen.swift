import CloudStorage
import Combine
import SwiftUI
import SonosKit
import VibesDS

struct SceneBuilderScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss
    
    var group: Binding<GroupRoom>? = nil
    @Binding var sheetDestination: SheetDestination?
    @State var selections = Set<String>()
    @State var sceneName: String = ""
    @State var rooms: [Room] = []
    @State var id: String?

    @State var groupVolume = 0.0
    @State var groupVolumeTask: Task<Void,Error>?

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some View {
        ZStack {
            Rectangle()
                .opacity(0.5)
                .foregroundStyle(.ultraThinMaterial)
                .ignoresSafeArea()
            List {
                ForEach($rooms) { $room in
                    VStack {
                        Button {
                            if selections.contains(room.id) {
                                selections.remove(room.id)
                            } else {
                                selections.insert(room.id)
                            }
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
                        .sensoryFeedback(.selection, trigger: selections.contains(room.id))
                        RoomVolumeView(room: $room, touchDelay: 0.05)
                            .foregroundStyle(selections.contains(room.id) ? .black : .primary)
                            .tint(selections.contains(room.id) ? .black : .accentColor)
                    }
                    .listRowBackground(
                        selections.contains(room.id) ? RoundedRectangle(cornerRadius: 12)
                            .foregroundStyle(Color.accentColor.gradient.opacity(0.8))
                        : nil
                    )
                    .task {
                        guard let group = group else { return }
                        selections.insert(group.wrappedValue.coordinatorRoom.id)
                    }
                }
//                NavigationLink("Add Playlist") {
//                    MusicSearchScreen()
//                }
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
                    VStack {
                        Text("All")
                            .bold()
                        HStack(alignment: .center) {
                            Image(systemName: "speaker.wave.3.fill", variableValue: groupVolume/100)
                            VibeSlider(value: $groupVolume, in: 0...100)
                            Text("\(groupVolume, specifier: "%03.0f")%")
                                .contentTransition(.numericText())
                                .monospacedDigit()
                                .animation(.spring.speed(5), value: groupVolume)
                                .frame(width: 50, alignment: .trailing)
                                .fontDesign(.rounded)
                        }
                        .onChange(of: groupVolume, initial: false) { _, newValue in
                            groupVolumeTask?.cancel()
                            groupVolumeTask = Task {
                                for room in rooms {
                                    room.volume = groupVolume
                                    await sonosService.setDeviceVolume(ip: room.ip, volume: Int(room.volume))
                                }
                            }
                        }
                    }
                    .padding([.horizontal, .bottom])
                    Button {
                        let rooms = rooms.filter { room in
                            selections.contains(room.id)
                        }
                        let sceneRooms = rooms.map { SceneRoom(id: $0.id, ip: $0.ip, name: $0.name, volume: $0.volume) }
                        let newScene = SonosScene(name: sceneName, rooms: sceneRooms, playableContent: PlayableContent(title: "", subtitle: "", artwork: nil, content: MediaContent(service: .spotify, id: "37i9dQZEVXcTv12cCWsQJf", type: .playlist, location: nil)))
                        scenes.append(newScene)
                        sheetDestination = nil
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
                    .disabled(selections.isEmpty)
                }
                .background {
                    RoundedRectangle(cornerRadius: 20)
                        .foregroundStyle(.ultraThinMaterial)
                        .edgesIgnoringSafeArea(.bottom)
                        .shadow(radius: 2)
                }
            }
            .listRowSpacing(10)
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
            .onChange(of: selections, initial: true) { oldValue, newValue in
                let rooms = rooms.filter { room in
                    selections.contains(room.id)
                }

                sceneName = rooms.map(\.name).joined(separator: " + ")
            }
            .task {
                guard OSEnvironment.isPreviews else { return }
                sonosService.monitor()
            }
            .task {
                try? await Task.sleep(for: .milliseconds(500))
                let id = await sonosService.getHouseID()
                print(id)
                self.id = id
            }
        }
    }
}

#Preview {
        Text("SceneBuilder")
            .sheet(isPresented: .constant(true)) {
                NavigationStack {
                    SceneBuilderScreen(group: .constant(.garage), sheetDestination: .constant(nil))
                        .onAppear {
                            let thumbImage = UIImage()
                            UISlider.appearance().setThumbImage(thumbImage, for: .normal)
                        }
                }
            }
            .environment(AlertService())
            .environment(SonosService())
}
