import MusicSearchKit
import NukeUI
import SwiftUI
import SonosKit

struct QueueScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService

    @Binding var group: GroupRoom
    @State private var tracks: [PlayableContent] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(tracks, id: \.trackID) { track in
                        HStack {
                            ThumbnailView(content: track)
                                .frame(width: 40, height: 40)
                            Button {
                                Task {
                                    guard let position = track.metadata?.position else { return }
                                    await sonosService.seek(trackNumber: position, on: group)
                                    await sonosService.play(ip: group.coordinatorRoom.ip)
                                }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(track.title)
                                        .lineLimit(1)
                                    Text(track.subtitle)
                                        .lineLimit(1)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        guard let position = track.metadata?.position else { return }
                                        tracks.remove(at: position - 1)
                                        Task {
                                            try? await sonosService.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
                                            tracks = await sonosService.getQueue(ip: group.coordinatorRoom.ip)
                                        }
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listRowBackground(isTrackPlaying(for: track) ? nil : Color.clear)
                        .bold(isTrackPlaying(for: track))
                    }
                    .fontDesign(.rounded)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .navigationTitle("Queue")
                .task {
                    await getQueue()
                }
                .task(id: tracks.count) {
                    withAnimation {
                        let id = group.coordinatorRoom.track.trackID + "\(group.coordinatorRoom.track.position)"
                        proxy.scrollTo(id)
                    }
                }
                .animation(.spring, value: tracks)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .padding()
                            .background(.thinMaterial)
                    }
                    if tracks.isEmpty, !isLoading {
                        ContentUnavailableView("Empty", systemImage: "music.note.list")
                            .transition(.opacity)
                    }
                }
            }
            .animation(Animation.default.delay(tracks.isEmpty ? 0 : 2), value: tracks)
        }
    }

    private func getQueue() async {
        isLoading = true
        defer { isLoading = false }
        self.tracks = await sonosService.getQueue(ip: group.ip)
    }

    private func isTrackPlaying(for song: PlayableContent) -> Bool {
        guard let position = song.metadata?.position else { return false }
        return group.coordinatorRoom.track.position == position && group.playbackService == .queue
    }
}

fileprivate struct ContainerView: View {
    @State var group: GroupRoom = .garage
    var body: some View {
        QueueScreen(group: $group)
            .environment(SonosService())
    }
}

#Preview {
    TabView {
        ContainerView()
    }
}

