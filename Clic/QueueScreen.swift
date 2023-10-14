import SwiftUI
import MusicSearchKit
import SonosKit

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
                }
            }
        )

        let isRepeat = Binding(
            get: {
                group.playMode.contains(.repeatOne)
            },
            set: {
                if $0 {
                    group.playMode.insert(.repeatOne)
                } else {
                    group.playMode.remove(.repeatOne)
                }
                Task {
                    await sonosService.setPlayMode(group.ip, mode: group.playMode)
                }
            }
        )

        NavigationStack {
            List {
                ForEach(Array(tracks.enumerated()), id: \.element.trackID) { index, track in
                    HStack {
                        AsyncImage(
                            url: track.artworkURL,
                            transaction: Transaction(animation: .snappy)
                        ) { phase in
                            switch phase {
                            case .success(let image):
                                image
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
                                                .foregroundStyle(.thickMaterial)
                                                .frame(width: 16, height: 16)
                                                .padding([.trailing, .bottom], 4)
                                        case .spotify:
                                            Image(.spotifyLogo)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .foregroundStyle(.thickMaterial)
                                                .frame(width: 16, height: 16)
                                                .padding([.trailing, .bottom], 4)
                                        case .airplay, .unknown:
                                            EmptyView()
                                        }
                                    }
                            case .failure:
                                EmptyView()
                            default:
                                RoundedRectangle(cornerRadius: 4)
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.ultraThinMaterial)
                                    .shadow(radius: 2)
                                    .frame(width: 60, height: 60)
                            }
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
                    .task {
                        guard let artworkURL = await sonosService.getArtwork(from: track) else {
                            return
                        }

                        track.artworkURL = artworkURL
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .toolbarBackground(.hidden, for: .bottomBar)
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

                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()
                    Toggle("Shuffle", systemImage: "shuffle.circle", isOn: isShuffle)
                        .contentShape(Circle())
//                    Toggle("Repeat", systemImage: "repeat.circle", isOn: isRepeat)
                }
            }
        }
        .task {
            self.tracks = await sonosService.getQueue(ip: group.ip)
            group.playMode = await sonosService.playMode(ip: group.ip)
        }
        .presentationBackground(.thinMaterial)
    }
}

#Preview {
    Text("Queue...")
        .sheet(isPresented: .constant(true)) {
            QueueScreen(group: .constant(.garage))
                .environment(SonosService())
                .presentationDetents([.medium, .large])
        }
}

