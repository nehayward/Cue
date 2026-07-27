import SwiftUI
import SonosKit
import SubscriptionKit
import CloudStorage
import VibesDS

struct GroupScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(AlertService.self) var alertService
    @Environment(SubscriptionService.self) var subscriptionService: SubscriptionService
    @Environment(\.dismiss) var dismiss

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    @State var group: GroupRoom?
    @State var coordinatorID: String
    @Binding var sheetDestination: SheetDestination?

    @State private var path: [Set<String>] = []
    @State private var selections: Set<String> = []
    @State private var groupVolume: Double = 0.0
    @State private var groupVolumeTask: Task<Void,Error>?

    init(coordinatorID: String, sheetDestination: Binding<SheetDestination?>) {
        self.coordinatorID = coordinatorID
        self._sheetDestination = sheetDestination
    }

    @AppStorage("groupScreen.sortOption") private var sortOption: SonosSortOption = .nameAscending

    private var activeRooms: [Room] {
        sonosService.sortedRooms.filter { $0.state == .active }
    }

    private var sortedActiveRooms: [Room] {
        switch sortOption {
        case .nameAscending:
            return activeRooms.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDescending:
            return activeRooms.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .playing:
            return activeRooms.sorted {
                sonosService.playbackRoom(for: $0).isPlaying && !sonosService.playbackRoom(for: $1).isPlaying
            }
        }
    }
    
    @ViewBuilder
    var backgroundShape: some View {
#if !os(visionOS)
        if #available(iOS 26.0, visionOS 26.0, macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 4)
                .glassEffect(in: .rect)
        } else {
            RoundedRectangle(cornerRadius: 4).foregroundStyle(.placeholder)
        }
#else
        RoundedRectangle(cornerRadius: 4).foregroundStyle(.placeholder)
#endif
    }

    var body: some View {
        @Bindable var sonosService = sonosService
        NavigationStack(path: $path) {
            List {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    Task {
                        _ = await sonosService.speedGroup(rooms: activeRooms)
                    }
                    dismiss()
                } label: {
                    Text("Everywhere")
                        .frame(maxWidth: .infinity)
                        .bold()
                }
                .buttonStyle(.bordered)
                .fontDesign(.rounded)
                .tint(.accent)
                .foregroundStyle(.accent)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)

                ForEach(sortedActiveRooms) { room in
                    VStack(spacing: 0) {
                        Button {
                            HapticManager.shared.fireHaptic(.selection)
                            addGroup(id: room.id)
                        } label: {
                            HStack {
                                // Grouped rooms hear the coordinator's stream, so show its track —
                                // a member room's own `track` goes stale once it joins a group.
                                let playbackRoom = sonosService.playbackRoom(for: room)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(room.name)
                                        .font(.headline)
                                        .fontWeight(.semibold)

                                    if !playbackRoom.track.name.isEmpty {
                                        Text(playbackRoom.track.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .foregroundStyle(playbackRoom.isPlaying ? .accent : .secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: selections.contains(room.id) ? "checkmark.circle.fill" : "circle")
                                    .contentTransition(.symbolEffect(.replace))
                                    .font(.title2)
                                    .opacity(isSelected(room) ? 1 : 0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.primary)
                            .fontDesign(.rounded)
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        RoomVolumeView(room: room, delayDrag: true)
                            .foregroundStyle(.primary)
                    }
                    .listRowBackground(selections.contains(room.id) ? backgroundShape : nil)
                    .listRowInsets(EdgeInsets())
                }
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All Speakers")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("\(activeRooms.count) rooms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fontDesign(.rounded)
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                    HStack {
                        Button {
                            groupVolume = max(0, groupVolume - 1)
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 24, height: 24)
                                .bold()
                        }
                        .buttonStyle(.plain)
                        .buttonRepeatBehavior(.enabled)

                        VibeSlider(value: $groupVolume, in: 0...100, baseHeight: UIDevice.current.userInterfaceIdiom == .phone ? 12 : 20)

                        Button {
                            groupVolume = min(100, groupVolume + 1)
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 24, height: 24)
                                .bold()
                        }
                        .buttonStyle(.plain)
                        .buttonRepeatBehavior(.enabled)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                    .onChange(of: groupVolume, initial: false) { _, newValue in
                        groupVolumeTask?.cancel()
                        groupVolumeTask = Task {
                            for room in activeRooms {
                                room.volume = groupVolume
                                await sonosService.setDeviceVolume(ip: room.ip, volume: Int(room.volume))
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
            }
            .contentMargins(.top, EdgeInsets(), for: .scrollContent)
            .navigationDestination(for: Set<String>.self) { ids in
                SceneBuilderScreen(selections: ids)
            }
            .listRowSpacing(10)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if let name = sonosService.sorted.first(where: { $0.coordinatorID == coordinatorID })?.nameWithCount {
                        HStack {
                            Text(name)
                                .animation(.snappy, value: sonosService.sorted)
                        }
                        .fontDesign(.rounded)
                        .bold()
                    } else {
                        ProgressView()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    SortMenuView(sortOption: $sortOption)
                    if subscriptionService.subscription.isActive {
                        NavigationLink(value: selections) {
                          if scenes.isEmpty {
                            Label("Create Scene", systemImage: "plus")
                          } else {
                            Label("Add", systemImage: "plus")
                                .labelStyle(.iconOnly)
                          }
                        }
                    } else {
                        Button {
                            sheetDestination = .paywall
                        } label: {
                            Text("Create Scene")
                        }
                    }
                }
            }
            .safeArea(edge: .bottom) {
                if !scenes.isEmpty {
                    HStack(spacing: 0) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.primary)
                            .font(.subheadline)
                            .padding(.leading, 12)
                            .padding(.trailing, 4)

                        SceneListView(editScene: { scene in
                            Router.main.sheet(to: .editScene(scene))
                        }, sceneActivated: { scene in
                            if let content = scene.playableContent {
                                alertService.showAlertContent(with: content, subtitle: "Running \(scene.name)", symbolName: "bolt.fill")
                            } else {
                                alertService.showAlert(with: "Running \(scene.name)")
                            }
                        })
                        .mask {
                            HStack(spacing: 0) {
                                LinearGradient(
                                    colors: [.clear, .black],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 16)
                                Rectangle()
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .foregroundStyle(.ultraThinMaterial)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .toolbarTitleDisplayMode(.inline)
            .addDismiss {
                dismiss()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .task {
            guard let foundGroup = sonosService.sorted.first(where: { $0.coordinatorID == coordinatorID }) else { return }
            group = foundGroup
            selections = Set(foundGroup.rooms.map { $0.id })
        }
        .task {
            try? await sonosService.load(useCache: true)
        }
        .animation(.default, value: selections)
        .animation(.default, value: sortOption)
        .animation(.default, value: sortedActiveRooms.map(\.id))
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
                        Router.main.selectedID = coordinatorID
                        Router.main.navigate(to: .player(groupID: coordinatorID))
                    }
                }
            }
        }
    }
    
    func isSelected(_ room: Room) -> Bool {
        selections.contains(room.id)
    }
}

fileprivate struct SortMenuView: View {
    @Binding var sortOption: SonosSortOption

    var body: some View {
        Menu {
            ForEach(SonosSortOption.allCases) { option in
                Toggle(isOn: Binding(
                    get: { sortOption == option },
                    set: { isOn in
                        if isOn {
                            sortOption = option
                        }
                    }
                )) {
                    Label {
                        Text(option.title)
                    } icon: {
                        option.icon
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .accessibilityLabel(Text("Sort by"))
        }
        .tint(.primary)
    }
}

#Preview {
    @Previewable @State var isPresented = true

    Text("HERE")
        .sheet(isPresented: $isPresented) {
            GroupScreen(coordinatorID: GroupRoom.gym.coordinatorID, sheetDestination: .constant(nil))
                .withEnvironments()
        }
}
