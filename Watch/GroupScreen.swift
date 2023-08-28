import SwiftUI
import SonosKit

struct GroupScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    @Bindable var roomGroup: GroupRoom
    @State var viewModel: GroupScreenViewModel

    var body: some View {
        List {
            ForEach(sonosService.rooms) { room in
                if room.id != roomGroup.coordinatorRoom.id {
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
                    let rooms = sonosService.rooms.filter { room in
                        viewModel.selections.contains(room.id)
                    }
                    Task {
                        dismiss()
                        await sonosService.smartGroup(rooms: rooms, to: roomGroup)
                    }
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
            if sonosService.rooms.isEmpty {
                do {
                    try await sonosService.load()
                } catch {
                    print(error)
                }
            }
        }
        .navigationTitle("\(roomGroup.coordinatorRoom.name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    Text("HERE")
        .sheet(isPresented: .constant(true), content: {
            GroupScreen(roomGroup: GroupRoom(id: "", coordinatorID: "", rooms: [
                Room(id: "", ip: "", name: "Kitchen")]), viewModel: GroupScreenViewModel(group: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "", name: "Kitchen")])))
            .environment(SonosService())
        })
}
