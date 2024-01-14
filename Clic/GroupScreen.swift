import SwiftUI
import SonosKit
import VibesDS

struct GroupScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    let id: String
    @Binding var sheetDestination: SheetDestination?
    @Bindable var viewModel: GroupScreenViewModel
    @State private var path: [Set<String>] = []
    @State private var groupVolume: Double = 0.0
    @State private var groupVolumeTask: Task<Void,Error>?

    var body: some View {
        NavigationStack(path: $path) {
            @Bindable var sonosService = sonosService
            List {
                ForEach($sonosService.sortedRooms.filter { $0.id != viewModel.group.coordinatorID }) { $room in
                    VStack {
                        Button {
                            viewModel.buttonAction(id: room.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(room.name)
                                        Spacer()
                                    }
                                }
                                Spacer()
                                Image(systemName: viewModel.selections.contains(room.id) ? "checkmark.circle.fill" : "checkmark.circle")
                                    .symbolEffect(.bounce, options: .speed(5), value: viewModel.selections.contains(room.id))
                            }
                            .foregroundStyle(viewModel.selections.contains(room.id) ? .black : .primary)
                            .fontDesign(.rounded)
                            .bold()
                        }
                        RoomVolumeView(room: $room, touchDelay: 0.05)
                            .foregroundStyle(viewModel.selections.contains(room.id) ? .black : .primary)
                            .tint(viewModel.selections.contains(room.id) ? .black : .accentColor)
                    }
                    .listRowBackground(
                        viewModel.selections.contains(room.id) ? RoundedRectangle(cornerRadius: 12)
                            .foregroundStyle(Color.accentColor.gradient.opacity(0.8) )
                        : nil
                    )
                    .sensoryFeedback(.selection, trigger: viewModel.selections.contains(room.id))
                }
            }
            .navigationDestination(for: Set<String>.self) { ids in
                SceneBuilderScreen(group: $viewModel.group, sheetDestination: $sheetDestination, selections: ids)
            }
            .listRowSpacing(10)
            .toolbar {
                ToolbarItem(placement: .principal) {
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

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Add Scene", value: viewModel.selections)
                        .animation(.spring, value: viewModel.selections.isEmpty)
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
                            for room in viewModel.sonosService.rooms {
                                room.volume = groupVolume
                                await viewModel.sonosService.setDeviceVolume(ip: room.ip, volume: Int(room.volume))
                            }
                        }
                    }
                    .padding(.bottom)
//                    Button {
//                        let rooms = sonosService.sortedRooms.filter { room in
//                            viewModel.selections.contains(room.id)
//                        }
//                        Task {
//                            dismiss()
//                            await sonosService.smartGroup(rooms: rooms, to: viewModel.group)
//                        }
//                    } label: {
//                        Text(viewModel.groupingLabel)
//                            .foregroundStyle(.ultraThickMaterial)
//                            .fontDesign(.rounded)
//                            .font(.title3)
//                            .bold()
//                            .frame(maxWidth: .infinity)
//                            .animation(nil, value: UUID())
//                    }
//                    .buttonStyle(.borderedProminent)
//                    .buttonBorderShape(.roundedRectangle)
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
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
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
