import SwiftUI
import SonosKit

struct GroupScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    @Binding var group: GroupRoom
    @State var viewModel: GroupScreenViewModel

    var body: some View {
        List {
            ForEach(sonosService.sortedRooms) { room in
                if room.id != group.coordinatorRoom.id {
                    Button {
                        viewModel.buttonAction(id: room.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(room.name)
                                Text("\(room.volume, specifier: "%0.f")%")
                            }
                            Spacer()
                            Image(systemName: viewModel.selections.contains(room.id) ? "checkmark.circle.fill" : "checkmark.circle")
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.groupingLabel != "Cancel" {
                Button {
                    let rooms = sonosService.sortedRooms.filter { room in
                        viewModel.selections.contains(room.id)
                    }
                    Task {
                        dismiss()
                        await sonosService.smartGroup(rooms: rooms, to: group)
                    }
//                    Task {
//                        await sonosService.smartGroup(rooms: rooms, to: roomGroup)
//                        try await sonosService.fetch()
//                        dismiss()
//                    }
                } label: {
                    Text(viewModel.groupingLabel)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .padding()
                .tint(.blue)
            }
        }
        .ignoresSafeArea(edges: .bottom)

//        .toolbar {
//            ToolbarItem(placement: .bottomBar) {
//                Button {
//                    let rooms = sonosService.rooms.filter { room in
//                        viewModel.selections.contains(room.id)
//                    }
//                    Task {
//                        dismiss()
//                        await sonosService.smartGroup(rooms: rooms, to: roomGroup)
//                    }
//                } label: {
//                    Text(viewModel.groupingLabel)
//                }
//                .buttonStyle(.bordered)
//            }
//        }
        .task {
            if sonosService.sortedRooms.isEmpty {
                do {
                    try await sonosService.load()
                } catch {
                    print(error)
                }
            }
        }
        .navigationTitle("\(group.coordinatorRoom.name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    Text("HERE")
        .sheet(isPresented: .constant(true)) {
            GroupScreen(group: .constant(.garage), viewModel: GroupScreenViewModel(group: .garage))
                .environment(SonosService())
        }
}
