import SwiftUI
import WatchKit
import SonosKit

struct GroupScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    @State var group: GroupRoom?
    @State private var coordinatorID: String
    @State private var selections: Set<String> = []

    init(coordinatorID: String) {
        self.coordinatorID = coordinatorID
    }

    var body: some View {
        @Bindable var sonosService = sonosService
        List {
            ForEach($sonosService.sortedRooms) { $room in
                Button {
                    WKInterfaceDevice.current().play(.click)
                    addGroup(id: room.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(room.name)
                                    .bold()
                                Spacer()
                            }
                            Text("\(room.volume, specifier: "%0.f")%")
                                .font(.caption)
                        }
                        Spacer()
                        Image(systemName: selections.contains(room.id) ? "checkmark.circle.fill" : "circle")
                            .symbolEffect(.bounce, options: .speed(3), value: selections.contains(room.id))
                    }
                    .foregroundStyle(selections.contains(room.id) ? .black : .primary)
                    .fontDesign(.rounded)
                }
                .listRowBackground(
                    selections.contains(room.id) ? RoundedRectangle(cornerRadius: 12)
                        .foregroundStyle( Color.accentColor.gradient.opacity(0.8) )
                    : nil
                )
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .task {
            if sonosService.sortedRooms.isEmpty {
                do {
                    try await sonosService.load(useCache: true)
                } catch {
                    print(error)
                }
            }
        }
        .navigationTitle("\(group?.nameWithCount ?? "Updating…")")
        .navigationBarTitleDisplayMode(.inline)
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
                        Router.main.selectedID = coordinatorID
                    }
                }
            }
        }

    }
}

//#Preview {
//    Text("HERE")
//        .sheet(isPresented: .constant(true)) {
//            GroupScreen(group: .constant(.garage), viewModel: GroupScreenViewModel(groupCoordinatorID: GroupRoom.garage.coordinatorID, sonosService: SonosService()))
//                .environment(SonosService())
//        }
//}
