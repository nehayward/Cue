import SwiftUI
import SonosKit
import SubscriptionKit
import CloudStorage
import VibesDS

struct TVGroupScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []
//    var scenes: [SonosScene] = [SonosScene(id: UUID(), name: "Main", rooms: [SceneRoom(id: "", ip: "", name: "", volume: 0)]), SonosScene(id: UUID(), name: "Test", rooms: [SceneRoom(id: "", ip: "", name: "", volume: 0)])]

    @State var group: GroupRoom?
    @State var coordinatorID: String
    
    @State private var path: [Set<String>] = []
    @State private var selections: Set<String> = []
    @State private var groupVolume: Double = 0.0
    @State private var groupVolumeTask: Task<Void,Error>?
    
    @FocusState private var focusedSceneID: UUID?

    
    public var sortedRoom: [Room] {
        sonosService.sortedRooms.filter { $0.state == .active }
            .sorted {
                let aSelected = selections.contains($0.id)
                let bSelected = selections.contains($1.id)
                if aSelected == bSelected {
                    return $0.name < $1.name // fallback sorting (e.g. alphabetically)
                }
                return aSelected && !bSelected
            }
    }
    
    init(coordinatorID: String) {
        self.coordinatorID = coordinatorID
    }
    
    var body: some View {
        @Bindable var sonosService = sonosService
        List {
            ForEach(sortedRoom) { room in
                VStack(spacing: 0) {
                    Button {
                        addGroup(id: room.id)
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
                }
                .listRowBackground(selections.contains(room.id) ? RoundedRectangle(cornerRadius: 12)
                    .foregroundStyle(.placeholder)
                                   : nil)
                .listRowInsets(EdgeInsets())
            }
            
            if !scenes.isEmpty {
                Section {
                    LazyHStack {
                        ForEach(scenes) { scene in
                            Button {
                                Task {
                                    try? await sonosService.runScene(scene)
                                }
                            } label: {
                                Text(scene.name)
                            }
                            .buttonStyle(.plain)
                            .focused($focusedSceneID, equals: scene.id)
                        }
                    }
                    .defaultFocus($focusedSceneID, scenes.first?.id)
                    .focusSection()
                } header: {
                    Text("Scenes")
                }
            }
        }
        .task {
            guard let foundGroup = sonosService.sorted.first(where: { $0.coordinatorID == coordinatorID }) else { return }
            group = foundGroup
            selections = Set(foundGroup.rooms.map { $0.id })
        }
        .task {
            try? await sonosService.load(useCache: true)
        }
        .background(.ultraThickMaterial)
    }
    
    private func addGroup(id: String) {
        if selections.contains(id), selections.count == 1 { return }
        let oldRooms = sonosService.sortedRooms.filter { room in selections.contains(room.id) }
        
        selections.formSymmetricDifference([id])
        let rooms = sonosService.sortedRooms.filter { selections.contains($0.id) }
        
        Task {
            guard let group = SonosService.shared.sorted.first(where: { $0.coordinatorID == coordinatorID }) else { return }
            let newCoordinatorID = await sonosService.smartGroup(rooms: rooms, oldRooms: oldRooms, to: group)
            if !selections.contains(group.coordinatorID) {
                // MARK: Reassign coordinatorID
                if let id = newCoordinatorID {
                    coordinatorID = id
                    Task { @MainActor in
                        //                        if Router.main.path.isEmpty { return }
                        
                        //                        Router.main.path.removeAll()
                        //                        Router.main.navigate(to: .player(groupID: coordinatorID))
                    }
                }
            }
        }
    }
    
    func isSelected(_ room: Room) -> Bool {
        selections.contains(room.id)
    }
}
