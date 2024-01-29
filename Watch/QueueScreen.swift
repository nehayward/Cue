import MusicSearchKit
import NukeUI
import SwiftUI
import SonosKit

struct QueueScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService

    @Binding var group: GroupRoom
    @State private var tracks: [Track] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(tracks.enumerated()), id: \.0) { index, track in
                        HStack {
                            LazyImage(url: track.artworkURL) { state in
                                if let image = state.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else if state.isLoading {
                                    RoundedRectangle(cornerRadius: 4)
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundStyle(.ultraThinMaterial)
                                        .shadow(radius: 2)
                                }
                            }
                            .processors([.resize(width: 50)])
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .shadow(radius: 2)
                            .frame(width: 50, height: 50)
                            .overlay(alignment: .bottomTrailing) {
                                switch track.musicService {
                                case .apple:
                                    Image(systemName: "apple.logo")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundStyle(.white.gradient)
                                        .frame(width: 10, height: 10)
                                        .padding([.trailing, .bottom], 4)
                                        .shadow(radius: 10)
                                case .spotify:
                                    Image(.spotifyLogo)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundStyle(.white.gradient)
                                        .frame(width: 10, height: 10)
                                        .padding([.trailing, .bottom], 4)
                                        .shadow(radius: 10)
                                case .airplay, .unknown:
                                    EmptyView()
                                        .padding([.trailing, .bottom], 12)
                                }
                            }
                            .task(id: track.name) {
                                guard let artworkURL = await sonosService.getArtwork(from: track, size: 100) else {
                                    return
                                }

                                track.artworkURL = artworkURL
                            }

                            Button {
                                Task {
                                    await sonosService.seek(trackNumber: index + 1, on: group)
                                    await sonosService.play(ip: group.coordinatorRoom.ip)
                                }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(track.name)
                                    Text(track.artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task {
                                            try? await sonosService.removeTrackFromQueue(group.coordinatorRoom.ip, index: index)
                                            tracks.remove(at: index)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .id(index)
                        .listRowBackground(group.coordinatorRoom.track.position == index + 1 ? nil : Color.clear)
                    }
                    .fontDesign(.rounded)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .navigationTitle("Queue")
                .toolbar {
                    ToolbarItem(placement: .destructiveAction) {
                        Button {
                            Task {
                                try await sonosService.clearQueue(group.coordinatorRoom.ip)
                                await getQueue()
                            }
                        } label: {
                            Text("Clear")
                        }
                    }
                }
                .task {
                    await getQueue()
                }
                .task(id: tracks.count) {
                    withAnimation {
                        print(group.coordinatorRoom.track.position - 1)
                        proxy.scrollTo(group.coordinatorRoom.track.position - 1)
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

