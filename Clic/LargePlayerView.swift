import SwiftUI
import SonosKit

struct LargePlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    var group: GroupRoom
    @State var selection: PresentationDetent = .large
    @Namespace var namespace
    @State var state = 1.0
    @State private var isEditing: Bool = false
    @State private var volume: Double = 0
    @State private var showGroup = false

    var body: some View {
        VStack(alignment: .center) {

            ArtworkView(group: group)
                .matchedGeometryEffect(id: "album", in: namespace)
                .cornerRadius(12)
                .frame(width: 300, height: 300)
                .padding(.bottom, 24)


            Text(group.coordinatorRoom.track.name)
            Text(group.coordinatorRoom.track.artist)
                .font(.caption)
                .padding(.bottom, 24)
            VStack {
                ProgressView(value: group.coordinatorRoom.track.playbackPosition, total: group.coordinatorRoom.track.duration)
                HStack {
                    Text(group.coordinatorRoom.track.timestamp)
                    Spacer()
                    Text(group.coordinatorRoom.track.remainingTimestamp)
                }
                .monospacedDigit()
                .fontDesign(.rounded)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 24)

            HStack(spacing: 24) {
                Button {

                } label: {
                    Image(systemName: "backward.end.fill")
                }
                Button(action: {
                    Task {
                        if group.coordinatorRoom.isPlaying {
                            await sonosService.pause(ip: group.coordinatorRoom.ip)
                        } else {
                            await sonosService.play(ip: group.coordinatorRoom.ip)
                        }
                    }
                }, label: {
                    Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(.tint, .thickMaterial)
                        .contentTransition(.symbolEffect(.automatic))
                })
                Button {
                    Task {
                        await sonosService.next(ip: group.coordinatorRoom.ip)
                    }
                } label: {
                    Image(systemName: "forward.end.fill")
                        .foregroundStyle(.tint, .thickMaterial)
                }
            }
            .font(.largeTitle)
            VolumeControlView(roomGroup: group)
                .padding(.bottom, 24)
            HStack {
                Button {
                    showGroup.toggle()
                } label: {
                    Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .task {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else { return }

            let track = Track(name: "Dance The Night", artist: "Dua Lipa", album: "Barbie The Album", musicService: .apple, duration: 60, playbackPosition: .zero)
            track.artworkURL = await sonosService.getArtwork(song: track.name, artist: track.artist, album: track.album)
            group.rooms[0].track = track
            group.coordinatorRoom.track.duration = 2000
            Task {
                repeat {
                    // code you want to repeat

                    try? await Task.sleep(for: .seconds(1)) // exception thrown when cancelled by SwiftUI when this view disappears.
                    group.rooms[0].track.playbackPosition += 1000

                } while (!Task.isCancelled)
            }

        }
        .navigationTitle(Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? "+" : "")"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGroup) {
            GroupScreen(roomGroup: group, viewModel: GroupScreenViewModel(group: group))
        }
    }
}

#Preview {
    NavigationStack {
        LargePlayerView(group: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "192.168.4.50", name: "Garage")]))
            .environment(SonosService())
    }
}
