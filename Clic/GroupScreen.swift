import SwiftUI
import SonosKit

struct GroupScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    @Bindable var roomGroup: GroupRoom
    @State var multiSelection = Set<String>()

    var body: some View {
        List(selection: $multiSelection) {
            Section {
                HStack {
                    ArtworkView(group: roomGroup)
                        .frame(width: 72, height: 72)
                    ZoneView(roomGroup: roomGroup)
                }
            }
            ForEach(sonosService.rooms) { room in
                HStack {
                    //                        Image(systemName: roomGroup.rooms.contains(room) ? "checkmark.circle" : "circle")

                        Text(room.name)

                }
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .overlay(alignment: .bottom) {
            Button {
                let rooms = sonosService.rooms.filter { room in
                    multiSelection.contains(room.id)
                }
                Task {
                    dismiss()
                    await sonosService.group(rooms: rooms, to: roomGroup.coordinatorID)
                }
            } label: {
                Text("Done")
                    .fontWeight(.bold)
            }
            .buttonStyle(.borderedProminent)
        }
        .environment(\.editMode, .constant(EditMode.active))
        .task {
            if sonosService.rooms.isEmpty {
                await sonosService.load()
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    Text("HERE")
        .sheet(isPresented: .constant(true), content: {
            GroupScreen(roomGroup: GroupRoom(id: "", coordinatorID: "", rooms: [
                Room(id: "", ip: "", name: "Kitchen")]))
            .environment(SonosService())
        })
}
