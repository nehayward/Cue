import SwiftUI
import SonosKit
import SubscriptionKit
import VibesDS

struct GroupScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SubscriptionService.self) var subscriptionService: SubscriptionService
    @Environment(\.dismiss) var dismiss

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
    
    var body: some View {
        @Bindable var sonosService = sonosService
        NavigationStack(path: $path) {
            List {
                ForEach($sonosService.sortedRooms) { $room in
                    VStack {
                        Button {
                            HapticManager.shared.fireHaptic(.selection)
                            addGroup(id: room.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(room.name)
                                        Spacer()
                                    }
                                }
                                Spacer()
                                Image(systemName: selections.contains(room.id) ? "checkmark.circle.fill" : "checkmark.circle")
                                    .symbolEffect(.bounce, options: .speed(3), value: selections.contains(room.id))
                            }
                            .foregroundStyle(selections.contains(room.id) ? .black : .primary)
                            .fontDesign(.rounded)
                            .bold()
                        }
                        RoomVolumeView(room: $room, touchDelay: 0.05)
                            .foregroundStyle(selections.contains(room.id) ? .black : .primary)
                            .tint(selections.contains(room.id) ? .black : .accentColor)
                    }
                    .listRowBackground(
                        selections.contains(room.id) ? RoundedRectangle(cornerRadius: 12)
                            .foregroundStyle(Color.accentColor.gradient.opacity(0.8) )
                        : nil
                    )
                }
                SceneListView()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets.init(top: 12, leading: 0, bottom: 12, trailing: 0))
            }
            .navigationDestination(for: Set<String>.self) { ids in
                if let foundGroup = SonosService.shared.sorted.first(where: { $0.coordinatorID == coordinatorID }) {
                    SceneBuilderScreen(group: .constant(foundGroup), sheetDestination: $sheetDestination, selections: ids)
                }
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

                ToolbarItem(placement: .topBarTrailing) {
                    if subscriptionService.subscription.isActive {
                        NavigationLink("Add Scene", value: selections)
                            .animation(.spring, value: selections.isEmpty)
                    } else {
                        Button {
                            sheetDestination = .paywall
                        } label: {
                            Text("Add Scene")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
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
                            .frame(width: 36, alignment: .trailing)
                            .fontDesign(.rounded)
                    }
                    .font(.caption)
                    .fontDesign(.rounded)
                    .onChange(of: groupVolume, initial: false) { _, newValue in
                        groupVolumeTask?.cancel()
                        groupVolumeTask = Task {
                            for room in sonosService.rooms {
                                room.volume = groupVolume
                                await sonosService.setDeviceVolume(ip: room.ip, volume: Int(room.volume))
                            }
                        }
                    }
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 20)
                        .foregroundStyle(.ultraThinMaterial)
                        .edgesIgnoringSafeArea(.bottom)
                        .shadow(radius: 2)
                }
            }
            .toolbarTitleDisplayMode(.inline)
            .addDismiss {
                dismiss()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .task(id: sonosService.sorted.first(where: { $0.coordinatorID == coordinatorID })?.rooms) {
            if sonosService.isGrouping { return }
            guard let foundGroup = SonosService.shared.sorted.first(where: { $0.coordinatorID == coordinatorID }) else { return }
            group = foundGroup
            selections = Set(foundGroup.rooms.map { $0.id })
        }
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
                        if Router.main.path.isEmpty { return }

                        Router.main.path.removeAll()
                        Router.main.navigate(to: .player(groupID: coordinatorID))
                    }
                }
            }
        }

    }
}

//#Preview {
//    Text("HERE")
//        .sheet(isPresented: .constant(true)) {
//            GroupScreen(sheetDestination: .constant(nil), viewModel: GroupScreenViewModel(groupCoordinatorID: GroupRoom.garage.coordinatorID, sonosService: SonosService()))
//                .environment(SonosService())
//                .onAppear {
//                    let thumbImage = UIImage()
//                    UISlider.appearance().setThumbImage(thumbImage, for: .normal)
//                }
//        }
//}
