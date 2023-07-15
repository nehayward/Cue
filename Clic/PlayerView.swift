import SwiftUI
import SonosKit

struct PlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    var group: GroupRoom
    @State var selection: PresentationDetent = .large
    @Namespace var namespace
    @State var state = 1.0
    @State private var isEditing: Bool = false
    @State private var volume: Double = 0


    var body: some View {
        if selection == .large {
            VStack {
                HStack {
                    ArtworkView(group: group)
                        .matchedGeometryEffect(id: "album", in: namespace)
                        .cornerRadius(12)
                        .frame(width: 300, height: 300)
                }
            }
        }
        VStack(alignment: .leading) {
            HStack(alignment: .center) {
                if selection != .large {
                    ArtworkView(group: group)
                        .matchedGeometryEffect(id: "album", in: namespace)
                        .cornerRadius(12)
                        .frame(width: 72, height: 72)
                }

                VStack(alignment: .leading) {
                    Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? "+" : "")")
                        .contextMenu {
                            ForEach(group.rooms) { room in
                                Text(room.name)
                            }
                        }
                    Text(group.coordinatorRoom.track.name)
                        .font(.caption)

                    HStack {
//                        Text(group.coordinatorRoom.track.playbackPosition, format: .number)
//                            .font(.caption)
//                            .matchedGeometryEffect(id: "title", in: namespace)
//                            .monospacedDigit()
//                        ProgressView(value: group.coordinatorRoom.track.playbackPosition, total: group.coordinatorRoom.track.duration)
//                            .tint(.primary)

                        Gauge(
                            value: group.coordinatorRoom.track.playbackPosition,
                            in: 0...group.coordinatorRoom.track.duration,
                            label: {

                            },
                            currentValueLabel: {
                                Text(group.coordinatorRoom.track.playbackPosition, format: .number)
                                    .font(.caption)
                                    .matchedGeometryEffect(id: "title", in: namespace)
                                    .monospacedDigit()
                                    .animation(nil, value: UUID())
                            },
                            markedValueLabels: {
//                                Text("0%").tag(0.0)
//                                Text("50%").tag(0.5)
//                                Text("100%").tag(1.0)
                            }
                        )
                        .gaugeStyle(.accessoryLinearCapacity)
                        .animation(.linear, value: group.coordinatorRoom.track.playbackPosition)
                    }
                }
                HStack {
//                    Button {
//
//                    } label: {
//                        Image(systemName: "backward.end.fill")
//                    }
                    Button(action: {
                        Task {
                            if group.coordinatorRoom.isPlaying {
                                await sonosService.pause(ip: group.coordinatorRoom.ip)
                            } else {
                                await sonosService.play(ip: group.coordinatorRoom.ip)
                            }
                        }
                    }, label: {
                        Image(systemName: group.coordinatorRoom.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .foregroundStyle(.tint, .thickMaterial)
                            .contentTransition(.symbolEffect(.replace.downUp))
                            .font(.largeTitle)
                    })
                    .buttonStyle(.plain)
                    Button {
                        Task {
                            await sonosService.next(ip: group.coordinatorRoom.ip)
                        }
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .foregroundStyle(.tint, .thickMaterial)
                            .font(.caption)
                    }
                }
            }
           VolumeControlView(roomGroup: group)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .task {
//            let track = Track(name: "Dance The Night", artist: "Dua Lipa", album: "Barbie The Album", musicService: .apple, duration: 60, playbackPosition: .zero)
//            track.artworkURL = await sonosService.getArtwork(song: track.name, artist: track.artist, album: track.album)
//            print(track.artworkURL)
//            group.rooms[0].track = track
//
//            Task {
//                repeat {
//                    // code you want to repeat
//
//                    try? await Task.sleep(for: .seconds(1)) // exception thrown when cancelled by SwiftUI when this view disappears.
//
//                    group.rooms[0].track.playbackPosition += 1
//
//                } while (!Task.isCancelled)
//            }

        }
        .presentationDetents([.fraction(0.2), .large], selection: $selection)
        .presentationBackgroundInteraction(.enabled)
        .presentationDragIndicator(.hidden)
        .presentationBackground(.thinMaterial)
        .interactiveDismissDisabled()
    }
}

#Preview {
    List {

    }.sheet(isPresented: .constant(true)) {
        PlayerView(group: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "192.168.4.50", name: "Garage")]))
            .environment(SonosService())
    }
}
