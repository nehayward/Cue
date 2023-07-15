import SwiftUI
import SonosKit

struct ZoneView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Popover.self) var popover: Popover

    var roomGroup: GroupRoom


    @State private var multiSelection = Set<String>()
    @State private var isEditing: Bool = false
    @State private var volume: Double = 0
    @State var show: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack {
                    VStack {
                        Text(roomGroup.coordinatorRoom.name + "\(roomGroup.rooms.count > 1 ? "+" : "")")
                            .contextMenu {
                                ForEach(roomGroup.rooms) { room in
                                    Text(room.name)
                                }
                            }
                    }
                    Spacer()
                }
                .fontDesign(.rounded)
                Text(roomGroup.coordinatorRoom.track.name)
                    .font(.caption)
               VolumeControlView(roomGroup: roomGroup)
            }
            VStack(spacing: 18) {
                Button(action: {
                    Task {
                        if roomGroup.coordinatorRoom.isPlaying {
                            await sonosService.pause(ip: roomGroup.coordinatorRoom.ip)
                        } else {
                            await sonosService.play(ip: roomGroup.coordinatorRoom.ip)
                        }
                    }
                }, label: {

                    Gauge(
                        value: roomGroup.coordinatorRoom.track.playbackPosition,
                        in: 0...roomGroup.coordinatorRoom.track.duration,
                        label: {

                        },
                        currentValueLabel: {
                            Image(systemName: roomGroup.coordinatorRoom.isPlaying ? "pause.circle.fill" : "play")
                                .foregroundStyle(.tint, .thickMaterial)
                                .contentTransition(.symbolEffect(.replace.downUp))
                                .font(.title)
                        },
                        markedValueLabels: {
    //                                Text("0%").tag(0.0)
    //                                Text("50%").tag(0.5)
    //                                Text("100%").tag(1.0)
                        }
                    )
                    .tint(Color.primary.gradient)
                    .gaugeStyle(.accessoryCircularCapacity)
                    .animation(.linear, value: roomGroup.coordinatorRoom.track.playbackPosition)
                    .scaleEffect(0.6)
                })
                .buttonStyle(.plain)



                Button(action: {
//                    multiSelection = Set(roomGroup.rooms.map(\.id))
//                    show = true

                    popover.isShowing = true
                }, label: {
                    Image(systemName: roomGroup.rooms.count > 1 ? "hifispeaker.2" :  "hifispeaker")
                        .frame(width: 20)
                        .foregroundStyle(.tint, .thickMaterial)
                })
                .buttonStyle(.plain)


            }.padding(.leading)
        }
        .padding(.leading)
        .onAppear {
            volume = roomGroup.coordinatorRoom.volume
        }
        .onChange(of: roomGroup.coordinatorRoom.volume) { oldValue, newValue in
            guard !isEditing else { return }
            withAnimation {
                volume = newValue
            }
        }
        .onChange(of: volume) { oldValue, newValue in
            if isEditing {
                Task {
                    await sonosService.setDeviceVolume(ip: roomGroup.coordinatorRoom.ip, volume: Int(newValue))
                }
            }
        }
        .background {
            EmptyView()
                .sheet(isPresented: $show) {
                    GroupScreen(roomGroup: roomGroup, multiSelection: multiSelection)
                }
        }
//        .task {
//            await sonosService.load()
//        }

//        .sheet(isPresented: $show) {
//            Text(roomGroup.coordinatorRoom.name)
//                .presentationDetenats([.fraction(0.2)])
//                .presentationDragIndicator(.visible)
//        }
    }
}

#Preview {
    List {
        Section {
            ZoneView(roomGroup: GroupRoom(id: "", coordinatorID: "Kitchen", rooms: [Room(id: "Kitchen", ip: "192", name: "Kitchen")]))
                .environment(SonosService())
        }
        Section {
            ZoneView(roomGroup: GroupRoom(id: "", coordinatorID: "Garage", rooms: [Room(id: "Garage", ip: "192", name: "Garage"), Room(id: "Kitchen", ip: "192", name: "Kitchen")]))
                .environment(SonosService())
        }
    }
}
