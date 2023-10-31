import SwiftUI
import MusicSearchKit
import SonosKit
import Kingfisher

struct QueueScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    @Binding var group: GroupRoom
    @State private var tracks: [Track] = []

    var body: some View {
        let isShuffle = Binding(
            get: {
                group.playMode.contains(.shuffle)
            },
            set: {
                if $0 {
                    group.playMode.insert(.shuffle)
                } else {
                    group.playMode.remove(.shuffle)
                }
                Task {
                    await sonosService.setPlayMode(group.ip, mode: group.playMode)
                    self.tracks = await sonosService.getQueue(ip: group.ip)
                }
            }
        )

        //        let isRepeat = Binding(
        //            get: {
        //                group.playMode.contains(.repeatOne)
        //            },
        //            set: {
        //                if $0 {
        //                    group.playMode.insert(.repeatOne)
        //                } else {
        //                    group.playMode.remove(.repeatOne)
        //                }
        //                Task {
        //                    await sonosService.setPlayMode(group.ip, mode: group.playMode)
        //                }
        //            }
        //        )

        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(tracks.enumerated()), id: \.0) { index, track in
                        HStack {
                            Text("\(index + 1)")
                            KFImage(track.artworkURL)
                                .placeholder {
                                    RoundedRectangle(cornerRadius: 4)
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundStyle(.ultraThinMaterial)
                                        .shadow(radius: 2)
                                }
                                .cacheMemoryOnly()
                                .fade(duration: 0.2)
                                .retry(DelayRetryStrategy(maxRetryCount: 3, retryInterval: .seconds(1)))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .shadow(radius: 2)
                                .frame(width: 60, height: 60)
                                .overlay(alignment: .bottomTrailing) {
                                    switch track.musicService {
                                    case .apple:
                                        Image(systemName: "apple.logo")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .foregroundStyle(.white.gradient)
                                            .frame(width: 16, height: 16)
                                            .padding([.trailing, .bottom], 4)
                                    case .spotify:
                                        Image(.spotifyLogo)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .foregroundStyle(.white.gradient)
                                            .frame(width: 16, height: 16)
                                            .padding([.trailing, .bottom], 4)
                                    case .airplay, .unknown:
                                        EmptyView()
                                            .padding([.trailing, .bottom], 4)
                                    }
                                }
                                .task(id: track.name) {
                                    guard let artworkURL = await sonosService.getArtwork(from: track) else {
                                        return
                                    }

                                    track.artworkURL = artworkURL
                                }

                            Button {
                                dismiss()
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
                        .listRowBackground(group.coordinatorRoom.track.position == index + 1 ? nil : Color.clear)
                    }
                    .fontDesign(.rounded)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Text("Queue")
                            .font(.title)
                    }
                    ToolbarItem(placement: .destructiveAction) {
                        Button {
                            Task {
                                try await sonosService.clearQueue(group.coordinatorRoom.ip)
                                tracks = await sonosService.getQueue(ip: group.coordinatorRoom.ip)
                            }
                        } label: {
                            Text("Clear")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Toggle("Shuffle", systemImage: "shuffle.circle", isOn: isShuffle)
                            .contentShape(Circle())
                            .toggleStyle(.button)
                            .padding()
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background(.thinMaterial)
                }
                .task {
                    self.tracks = await sonosService.getQueue(ip: group.ip)
                    group.playMode = await sonosService.playMode(ip: group.ip)
                    withAnimation {
                        proxy.scrollTo(group.coordinatorRoom.track.position - 1)
                    }
                }
                .animation(.spring, value: tracks)
            }
        }
        .presentationBackground(.thinMaterial)
    }
}

fileprivate struct ContainerView: View {
    @State var group: GroupRoom = .garage

    var body: some View {
        QueueScreen(group: $group)
            .environment(SonosService())
            .presentationDetents([.medium, .large])
    }
}

#Preview {
    Text("Queue...")
        .sheet(isPresented: .constant(true)) {
            ContainerView()
        }
}

