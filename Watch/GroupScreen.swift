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
                            Text(room.name)
                            Spacer()
                            Image(systemName: viewModel.selections.contains(room.id) ? "checkmark.circle.fill" : "checkmark.circle")
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
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
            }

            ToolbarItem(placement: .destructiveAction) {
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
            }

        }
        .task {
            if sonosService.rooms.isEmpty {
                await sonosService.load()
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
