import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI

struct QueueScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    @Binding var group: GroupRoom
    @State private var tracks: [Track] = []
    @State private var isLoading: Bool = true

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(tracks.enumerated()), id: \.0) { index, track in
                        HStack {
                            LazyImage(url: track.artworkURL) { state in
                                if let image = state.image {
                                    image.resizable().aspectRatio(contentMode: .fit)
                                } else {
                                    RoundedRectangle(cornerRadius: 4)
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundStyle(.ultraThinMaterial)
                                        .shadow(radius: 2)
                                }
                            }
                            .processors([.resize(width: 60)])
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
                                guard let artworkURL = await sonosService.getArtwork(from: track, size: 200) else {
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
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    tracks.remove(at: index)
                                    Task {
                                        try? await sonosService.removeTrackFromQueue(group.coordinatorRoom.ip, index: index)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .listRowBackground(group.coordinatorRoom.track.position == index + 1 ? nil : Color.clear)
                    }
                    .onMove(perform: move)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        VStack(alignment: .leading) {
                            Text("Queue")
                                .bold()
                            Text(tracks.count, format: .number)
                                .contentTransition(.numericText())
                                .foregroundStyle(.secondary)
                        }
                    }

                    ToolbarItemGroup(placement: .topBarTrailing) {
//                        Toggle("Shuffle", systemImage: "shuffle", isOn: isShuffle)
//                            .toggleStyle(.button)
//                        let isShuffle = Binding(
//                            get: {
//                                group.playMode.contains(.shuffle)
//                            },
//                            set: {
//                                if $0 {
//                                    group.playMode.insert(.shuffle)
//                                } else {
//                                    group.playMode.remove(.shuffle)
//                                }
//                                Task {
//                                    await sonosService.setPlayMode(group.ip, mode: group.playMode)
//                                    self.tracks = await sonosService.getQueue(ip: group.ip)
//                                }
//                            }
//                        )

                        Button {
                            var currentPlayMode = group.playMode
                            if currentPlayMode.contains(.shuffle) {
                                currentPlayMode.remove(.shuffle)
                            } else {
                                currentPlayMode.insert(.shuffle)
                            }
                            Task {
                                group.playMode = currentPlayMode
                                await sonosService.setPlayMode(group.ip, mode: currentPlayMode)
                                self.tracks = await sonosService.getQueue(ip: group.ip)
                            }
                        } label: {
                            Image(systemName: "shuffle")
                                .tint(group.playMode.contains(.shuffle) ? .accentColor : .secondary)
                                .contentTransition(.symbolEffect(.automatic))
                        }

                        Button {
                            var currentPlayMode = group.playMode

                            if !currentPlayMode.contains(.repeatAll) {
                                currentPlayMode.remove(.normal)
                                currentPlayMode.insert(.repeatAll)
                            } else if currentPlayMode.contains(.repeatAll) {
                                currentPlayMode.remove(.normal)
                                currentPlayMode.remove(.repeatAll)
                                currentPlayMode.insert(.repeatOne)
                            } else {
                                currentPlayMode.remove(.repeatOne)
                                currentPlayMode.remove(.repeatAll)
                            }

                            Task {
                                group.playMode = currentPlayMode
                                await sonosService.setPlayMode(group.ip, mode: currentPlayMode)
                                self.tracks = await sonosService.getQueue(ip: group.ip)
                            }
                        } label: {
                            Image(systemName: group.playMode.contains(.repeatOne) ? "repeat.1" : "repeat")
                                .tint(group.playMode.rawValue > 2 ? .accentColor : .secondary)
                                .contentTransition(.symbolEffect(.automatic))
                        }
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
                #if os(visionOS)
                .addDismiss {
                    dismiss()
                }
                #endif
                .task(id: group) {
                    isLoading = true
                    self.tracks = await sonosService.getQueue(ip: group.ip)
                    group.playMode = await sonosService.playMode(ip: group.ip)
                    isLoading = false
                    withAnimation {
                        proxy.scrollTo(group.coordinatorRoom.track.position - 1)
                    }
                }
                .animation(.spring, value: tracks)
            }
        }
        .presentationBackground(.thinMaterial)
        .overlay {
            if isLoading, tracks.isEmpty {
                ProgressView()
            }
            if tracks.isEmpty, !isLoading {
                ContentUnavailableView("Empty", systemImage: "music.note.list")
                    .transition(.opacity)
            }
        }
        .fontDesign(.rounded)
    }

    func move(from source: IndexSet, to destination: Int) {
        tracks.move(fromOffsets: source, toOffset: destination)
        Task {
            guard let sourceIndex = source.first else { return }
            try await sonosService.reorderQueue(group, from: sourceIndex + 1, to: destination + 1)
        }
    }
}

fileprivate struct ContainerView: View {
    @State var group: GroupRoom = .garage

    var body: some View {
        QueueScreen(group: $group)
            .environment(SonosService.shared)
            .presentationDetents([.medium, .large])
    }
}

#Preview("Queue Garage") {
    Text("Queue...")
        .sheet(isPresented: .constant(true)) {
            QueueScreen(group: .constant(.garage))
                .environment(SonosService.shared)
                .presentationDetents([.medium, .large])
        }
}

//#Preview {
//    Text("Queue...")
//        .sheet(isPresented: .constant(true)) {
//            ContainerView()
//        }
//}
