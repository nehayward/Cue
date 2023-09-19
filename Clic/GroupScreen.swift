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
                                    Text("\(room.volume, specifier: "%0.f")%")
                                        .foregroundStyle(.secondary)
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
                    Button {
                        let rooms = sonosService.sortedRooms.filter { room in
                            viewModel.selections.contains(room.id)
                        }
                        Task {
                            dismiss()
                            await sonosService.smartGroup(rooms: rooms, to: group)
                        }
                    } label: {
                        Text(viewModel.groupingLabel)
                    }
                    .buttonStyle(.borderedProminent)
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
                if sonosService.sortedRooms.isEmpty {
                    do {
                        try await sonosService.load(useCache: true)
                    } catch {
                        print(error)
                    }
                }
            }
            .navigationTitle("\(group.coordinatorRoom.name)")
            .navigationBarTitleDisplayMode(.inline)
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
