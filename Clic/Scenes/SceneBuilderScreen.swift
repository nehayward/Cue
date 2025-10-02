import Analytics
import CloudStorage
import Combine
import SwiftUI
import SonosKit
import VibesDS

struct SceneBuilderScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    @State var edit: Bool = false
    @State var scene: SonosScene = SonosScene()
    @State var selections = Set<String>()
    @State private var rooms: [Room] = []
    @State private var router = Router()
    @State private var firstAppear: Bool = true
    @State private var showSpeakers: Bool = false
    @State var contentToAdd: ContentToAdd = ContentToAdd(add: true)

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some View {
        List {
            Section {
                TextField("Scene Name", text: $scene.name)
                NavigationLink {
                   RoomSpeakerScreen(scene: $scene, selections: $selections, rooms: $rooms)
                } label: {
                    VStack(alignment: .leading) {
                        ForEach(scene.rooms) { room in
                            HStack(spacing: 4) {
                                Text("\(room.name)")
                                Text("\(room.volume, specifier: "%03.0f")%")
                            }
                        }
                    }
                    if selections.isEmpty {
                        Text("Select at least one room")
                    }
                }
            }
            
            if let content = contentToAdd.content {
                Button {
                    router.presentedSheet = .sceneSearchAdd(adding: contentToAdd)
                } label: {
                    PlayableContentView(item: content, hideDetails: true)
                        .listRowBackground(Color.clear)
                        .foregroundStyle(.primary)
                        .disabled(true)
                        .overlay(alignment: .trailing) {
                            Button {
                                contentToAdd.content = nil
                            } label: {
                               Image(systemName: "x.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                }
                
                HStack {
                    Text("Play Mode")
                    Spacer()
                    Button {
                        guard var playMode = scene.playMode else {
                            scene.playMode = [.shuffle]
                            return
                        }

                        playMode.formSymmetricDifference(.shuffle) // toggles shuffle
                        scene.playMode = playMode
                    } label: {
                        Image(systemName: "shuffle")
                            .foregroundStyle(scene.playMode?.contains(.shuffle) == true ? .accent : .secondary)
                            .contentTransition(.symbolEffect(.automatic))
                    }
                    .buttonStyle(.plain)

                                         // MARK: - Repeat Mode Cycle
                     Button {
                         guard var playMode = scene.playMode else {
                             scene.playMode = [.repeatAll]
                             return
                         }

                         // Cycle: normal → repeatAll → repeatOne → normal
                         if playMode.contains(.normal) || playMode.rawValue == 1 {
                             playMode.remove(.normal)
                             playMode.insert(.repeatAll)
                         } else if playMode.contains(.repeatAll) {
                             playMode.remove(.normal)
                             playMode.remove(.repeatAll)
                             playMode.insert(.repeatOne)
                         } else {
                             playMode.remove(.repeatOne)
                             playMode.remove(.repeatAll)
                         }

                         scene.playMode = playMode
                     } label: {
                         Image(systemName: scene.playMode?.contains(.repeatOne) == true ? "repeat.1" : "repeat")
                             .foregroundStyle(scene.playMode?.rawValue ?? 0 > 2 ? .accent : .secondary)
                             .contentTransition(.symbolEffect(.automatic))
                     }
                    .buttonStyle(.plain)
                }
                
                Picker("Queue Position", selection: $scene.position) {
                    Text("Playing next").tag(QueuePosition.next)
                    Text("Playing now").tag(QueuePosition.now)
                    Text("Added to the front of the queue").tag(QueuePosition.front)
                    Text("Playing last").tag(QueuePosition.end)
                    Text("Replace Queue").tag(QueuePosition.replace)
                }
                .pickerStyle(.menu)
            } else {
                Button {
                    router.presentedSheet = .sceneSearchAdd(adding: contentToAdd)
                } label: {
                    Label("Add Music to Scene", systemImage: "music.note")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(edit ? scene.name : "Scene")
                }
                .fontDesign(.rounded)
                .bold()
                .padding(.vertical)
            }
        }
        .safeArea(edge: .bottom) {
            VStack {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    let rooms = rooms.filter { room in
                        selections.contains(room.id)
                    }
                    if !edit {
                        let sceneRooms = rooms.map { SceneRoom(id: $0.id, ip: $0.ip, name: $0.name, volume: $0.volume) }
                        scene.rooms = sceneRooms
                    }
                    
                    scene.playableContent = contentToAdd.content
                    if edit {
                        if let index = scenes.firstIndex(where: { $0.id == scene.id }) {
                            scenes[index] = scene
                        }
                    } else {
                        scenes.append(scene)
                    }
                    Analytics.shared.track(.createdScene)
                    dismiss()
                } label: {
                    Text(edit ? "Update Scene" : "Create Scene")
                        .foregroundStyle(.ultraThickMaterial)
                        .frame(maxWidth: .infinity)
                        .fontWeight(.bold)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .buttonBorderShape(.capsule)
                .disabled(selections.isEmpty || scene.name.isEmpty)
            }
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .foregroundStyle(.ultraThinMaterial)
                    .edgesIgnoringSafeArea(.bottom)
                    .shadow(radius: 1)
            }
        }
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
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
            if !edit, firstAppear {
                scene.name = rooms.map(\.name).joined(separator: " + ")
                let rooms = rooms.filter { room in
                    selections.contains(room.id)
                }
                let sceneRooms = rooms.map { SceneRoom(id: $0.id, ip: $0.ip, name: $0.name, volume: $0.volume) }
                scene.rooms = sceneRooms
                firstAppear = false
            } else {
                contentToAdd.content = scene.playableContent
                if selections.isEmpty {
                    selections = Set(scene.rooms.map(\.id))
                }
            }
        }
        .contentMargins(.top, EdgeInsets(), for: .scrollContent)
        .onAppear {
            Analytics.shared.track(.viewedSceneBuilderScreen)
        }
        .onChange(of: contentToAdd.content) {
            scene.playableContent = contentToAdd.content
        }
        .sheet(isPresented: $showSpeakers) {
            NavigationStack {
                RoomSpeakerScreen(scene: $scene, selections: $selections, rooms: $rooms)
            }
        }
        .presentationSizingiOS18()
        .addDismiss {
            dismiss()
        }
        .listStyle(.insetGrouped)
    }
    
    func isSelected(_ room: Room) -> Bool {
        selections.contains(room.id)
    }
}

fileprivate struct RoomSpeakerScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    var isEditing: Bool = false
    @Binding var scene: SonosScene
    @Binding var selections: Set<String>
    @Binding var rooms: [Room]
    
    @State private var groupVolume: Double = 0.0
    @State private var groupVolumeTask: Task<Void,Error>?
    
    var body: some View {
        List {
            ForEach($rooms) { $room in
                VStack(spacing: 8) {
                    Button {
                        HapticManager.shared.fireHaptic(.selection)
                        if selections.contains(room.id) {
                            selections.remove(room.id)
                            scene.rooms.removeAll { $0.id == room.id }
                        } else {
                            selections.insert(room.id)
                            let sceneRoom = SceneRoom(id: room.id, ip: room.ip, name: room.name, volume: room.volume)
                            scene.rooms.append(sceneRoom)
                        }
                        let rooms = rooms.filter { room in
                            selections.contains(room.id)
                        }
                        if scene.name.isEmpty {
                            scene.name = rooms.map(\.name).joined(separator: " + ")
                        }
                    } label: {
                        HStack {
                            Text(room.name)
                                .font(.title3)
                                .bold()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: selections.contains(room.id) ? "checkmark.circle.fill" : "circle")
                                .symbolEffect(.bounce, options: .speed(3), value: selections.contains(room.id))
                                .bold(isSelected(room))
                                .font(.title2)
                                .opacity(isSelected(room) ? 1 : 0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.primary)
                        .fontDesign(.rounded)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    RoomVolumeView(room: $room, delayDrag: true)
                        .foregroundStyle(.primary)
                }
                .listRowBackground(selections.contains(room.id) ? RoundedRectangle(cornerRadius: 12)
                    .foregroundStyle(.placeholder)
                                   : nil)
            }
        }
        .listRowSpacing(8)
        .safeArea(edge: .bottom) {
            VStack {
                Text("Selected Speakers")
                    .bold()
                HStack(alignment: .center, spacing: 0) {
                    VibeSlider(value: $groupVolume, in: 0...100, baseHeight: UIDevice.current.userInterfaceIdiom == .phone ? 12 : 20)
                    Text("\(groupVolume, specifier: "%03.0f")%")
                        .contentTransition(.numericText())
                        .monospacedDigit()
                        .animation(.spring.speed(5), value: groupVolume)
                        .frame(width: 36, alignment: .trailing)
                        .fontDesign(.rounded)
                }
                .font(.caption)
                .fontDesign(.rounded)
                .onChange(of: groupVolume, initial: false) { _, newValue in
                    groupVolumeTask?.cancel()
                    groupVolumeTask = Task {
                        for room in rooms {
                            if isSelected(room) {
                                room.volume = groupVolume
                                await sonosService.setDeviceVolume(ip: room.ip, volume: Int(room.volume))
                            }
                        }
                    }
                }
                .frame(height: 32)
                .foregroundStyle(.primary)
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .top])
            .background(.thickMaterial)
            .task {
                for room in scene.rooms {
                    await sonosService.setDeviceVolume(ip: room.ip, volume: Int(room.volume))
                    rooms.first { $0.id == room.id }?.volume = room.volume
                }
            }
            .onDisappear {
                for room in rooms {
                    guard let index = scene.rooms.firstIndex(where: { $0.id == room.id }) else { continue }
                    scene.rooms[index].volume = room.volume
                }
            }
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
