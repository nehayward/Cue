import SwiftUI
import SonosKit

struct GroupScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    @Binding var group: GroupRoom
    @State var viewModel: GroupScreenViewModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(sonosService.sortedRooms) { room in
                    if room.id != group.coordinatorRoom.id {
                        Button {
                            viewModel.buttonAction(id: room.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(room.name)
                                        .fontDesign(.rounded)
                                    HStack {
                                        Image(systemName: "speaker.wave.3.fill", variableValue: room.volume/100)
                                            .padding(.trailing, 8)
                                        Text("\(room.volume, specifier: "%0.f")%")
                                    }
                                }
                                Spacer()
                                Image(systemName: viewModel.selections.contains(room.id) ? "checkmark.circle.fill" : "checkmark.circle")
                                    .contentTransition(.symbolEffect(.automatic))

                            }
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
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
                            Text("Done")
                                .fontDesign(.rounded)
                                .bold()
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .padding()
                    }
                }
                ToolbarItem(placement: .navigation) {
                    HStack {
                        Image(systemName: "hifispeaker.fill")
                        Text(group.coordinatorRoom.name + viewModel.numberInGroup)
                    }
                    .fontDesign(.rounded)
                    .bold()
                }
            }
            .task {
                if sonosService.sortedRooms.isEmpty {
                    do {
                        try await sonosService.load(useCache: true)
                    } catch {
                        print(error)
                    }
                }
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    Text("HERE")
        .sheet(isPresented: .constant(true)) {
            GroupScreen(group: .constant(.garage), viewModel: GroupScreenViewModel(group: .garage))
            .environment(SonosService())
        }
}
