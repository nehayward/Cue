import SwiftUI
import SonosKit

struct GroupScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    @Binding var group: GroupRoom
    @State var viewModel: GroupScreenViewModel

    var body: some View {
        List {
            ForEach(sonosService.sortedRooms.filter { $0.id != viewModel.group.coordinatorID }) { room in
                Button {
                    viewModel.buttonAction(id: room.id)
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
                        Image(systemName: viewModel.selections.contains(room.id) ? "checkmark.circle.fill" : "checkmark.circle")
                            .symbolEffect(.bounce, options: .speed(5), value: viewModel.selections.contains(room.id))
                    }
                    .foregroundStyle(viewModel.selections.contains(room.id) ? .black : .primary)
                    .fontDesign(.rounded)
                }
                .listRowBackground(
                    viewModel.selections.contains(room.id) ? RoundedRectangle(cornerRadius: 12)
                        .foregroundStyle( Color.accentColor.gradient.opacity(0.8) )
                    : nil
                )
                .sensoryFeedback(.selection, trigger: viewModel.selections.contains(room.id))
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
//        .navigationTitle("\(group.coordinatorRoom.name)")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack {
                    Image(systemName: viewModel.selections.count > 0 ? "hifispeaker.2.fill" :  "hifispeaker.fill")
                        .animation(nil, value: UUID())
                    Text(viewModel.group.coordinatorRoom.name)
                        .animation(nil, value: UUID())
                    Text(viewModel.grouping)
                        .animation(nil, value: UUID())
                    Text(viewModel.numberInGroup)
                        .contentTransition(.numericText())
                }
                .fontDesign(.rounded)
                .bold()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    Text("HERE")
        .sheet(isPresented: .constant(true)) {
            GroupScreen(group: .constant(.garage), viewModel: GroupScreenViewModel(groupCoordinatorID: GroupRoom.garage.coordinatorID, sonosService: SonosService()))
                .environment(SonosService())
        }
}
