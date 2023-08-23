import SwiftUI
import SonosKit

struct LargePlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    var group: GroupRoom

    @State private var isEditing: Bool = false
    @State private var volume: Double = 0
    @State private var showGroup = false
    @State private var showSearch = false
    @State private var showQueue = false

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .center) {
            ArtworkView(group: group)
                .cornerRadius(12)
                .padding(.bottom, 24)
                .shadow(radius: 10)

            Text(group.coordinatorRoom.track.name)
                .multilineTextAlignment(.center)
                .fontDesign(.rounded)
            Text(group.coordinatorRoom.track.artist)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.bottom, 80)
            VStack {
                ProgressView(value: group.coordinatorRoom.track.playbackPosition, total: group.coordinatorRoom.track.duration)
                    .tint(.primary)
                    .progressViewStyle(.linear)
                HStack {
                    Text(group.coordinatorRoom.track.timestamp)
                    Spacer()
                    Text(group.coordinatorRoom.track.remainingTimestamp)
                }
                .monospacedDigit()
                .font(.caption)
            }
            .fontDesign(.rounded)
            .padding(.bottom, 24)

            HStack(spacing: 24) {
                Button {
                    Task {
                        await sonosService.previous(ip: group.coordinatorRoom.ip)
                    }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)

                Button{
                    Task {
                        if group.coordinatorRoom.isPlaying {
                            await sonosService.pause(ip: group.coordinatorRoom.ip)
                        } else {
                            await sonosService.play(ip: group.coordinatorRoom.ip)
                        }
                    }
                } label: {
                    Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.automatic))
                        .font(.title)
                }
                .buttonStyle(.plain)
                Button {
                    Task {
                        await sonosService.next(ip: group.coordinatorRoom.ip)
                    }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 40)


//            VolumeControlView(roomGroup: group)
//                .padding(.bottom, 24)
//            HStack {
//                Button {
//                    showGroup.toggle()
//                } label: {
//                    Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill")
//                        .font(.body)
//                        .foregroundStyle(.ultraThickMaterial)
//                }
//            }
        }
        .padding()
        .frame(maxHeight: .infinity)
        .task {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else { return }

            let track = Track(name: "Dance The Night", artist: "Dua Lipa", album: "Barbie The Album", musicService: .apple, duration: 60, playbackPosition: .zero)
            track.artworkURL = await sonosService.getArtwork(from: track)
            group.rooms[0].track = track
            group.coordinatorRoom.track.duration = 2000
            Task {
                repeat {
                    try? await Task.sleep(for: .seconds(1)) // exception thrown when cancelled by SwiftUI when this view disappears.
                    group.rooms[0].track.playbackPosition += 1000

                } while (!Task.isCancelled)
            }

        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    Image(systemName: "hifispeaker")
                    Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
                }
                .fontDesign(.rounded)
                .bold()
            }
            ToolbarItem(placement: .bottomBar) {
                HStack(spacing: 24) {
                    Button {
                        showGroup.toggle()
                    } label: {
                        Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill")
                            .font(.body)
                    }
                    .fontDesign(.rounded)
                    .buttonStyle(.plain)
                    .font(.body)
                    Button {
                        showSearch.toggle()
                    } label: {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.body)
                    }
                    .fontDesign(.rounded)
                    .buttonStyle(.plain)
                    .font(.body)

                    Button {
                        showQueue.toggle()
                    } label: {
                        Image(systemName: "music.note.list")
                            .font(.body)
                    }
                    .fontDesign(.rounded)
                    .buttonStyle(.plain)
                    .font(.body)
                }
            }
        }
        .sheet(isPresented: $showGroup) {
            GroupScreen(group: group, viewModel: GroupScreenViewModel(group: group))
        }
        .sheet(isPresented: $showSearch) {
            MusicSearchScreen(group: group)
        }
        .sheet(isPresented: $showQueue) {
            QueueScreen(group: group)
                .presentationDetents([.medium, .large])
        }
//        .toolbar(isExpanded ? .hidden : .automatic, for: .bottomBar)
//        .toolbar(isExpanded ? .hidden : .automatic, for: .navigationBar)
        .background {
            ZStack {
                AsyncImage(
                    url: group.coordinatorRoom.track.artworkURL,
                    transaction: Transaction(animation: .snappy)
                ) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .scaleEffect(2)
                            .blur(radius: 50)
                    default:
                        RoundedRectangle(cornerRadius: 4)
                            .foregroundStyle(.thinMaterial)
                            .shadow(radius: 2)
                            .scaleEffect(3)
                    }
                }
                Rectangle()
                    .foregroundStyle(.thinMaterial)
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                Rectangle()
                    .foregroundStyle(.ultraThinMaterial)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .opacity(isExpanded ? 1 : 0)
                    .onTapGesture {
                        withAnimation(.bouncy(duration: 0.3)) {
                            isExpanded = false
                        }
                    }
                GroupVolumeControlView(group: group, isExpanded: $isExpanded)
            }
        }
    }
    
}

#Preview {
    NavigationStack {
        LargePlayerView(group: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "192.168.4.50", name: "Garage")]))
            .environment(SonosService())
    }
}
