import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI

struct QueueScreen: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.isPresented) var isPresented
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router?

    @Binding var group: GroupRoom
    @State private var viewRouter = Router()
    @State private var tracks: [Track] = []
    @State private var isLoading: Bool = true

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(tracks) { track in
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
                                case .library:
                                    Image(systemName: "books.vertical.fill")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundStyle(.white.gradient)
                                        .frame(width: 16, height: 16)
                                        .padding([.trailing, .bottom], 4)
                                case .plex:
                                    Image(.plex)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundStyle(.white.gradient)
                                        .frame(width: 16, height: 16)
                                        .padding([.trailing, .bottom], 4)
                                case .tidal:
                                    MediaSearchService.tidal.icon
                                        .foregroundStyle(.white.gradient)
                                        .frame(width: 16, height: 16)
                                        .padding([.trailing, .bottom], 4)
                                }
                            }
                            .task(id: track.id) {
                                guard let artworkURL = await sonosService.getArtwork(from: track, size: 200) else {
                                    return
                                }
                                track.downloadedArtworkURL = artworkURL
                            }

                            Button {
                                dismiss()
                                Task {
                                    await sonosService.seek(trackNumber: track.position, on: group)
                                    await sonosService.play(ip: group.coordinatorRoom.ip)
                                }
                            } label: {
                                VStack(alignment: .leading) {
//                                    Text(track.artworkURL?.absoluteString ?? "--")
//                                        .textSelection(.enabled)
//                                    Text(track.position, format: .number) // MARK: Debug Only
                                    Text(track.name)
                                        .lineLimit(1)
                                    Text(track.artist)
                                        .lineLimit(1)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    tracks.remove(at: track.position - 1)
                                    Task {
                                        try? await sonosService.removeTrackFromQueue(group.coordinatorRoom.ip, index: track.position)
                                        tracks = await sonosService.getQueue(ip: group.coordinatorRoom.ip)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .id(track.id)
                        .listRowBackground(isTrackPlaying(for: track) ? Color(uiColor: UIColor.systemFill) : Color.clear)
                        .draggable(track.toPlayable)
                    }
                    .onMove(perform: move)
                }
                .saturation(group.playbackService == .queue ? 1 : 0.1 )
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        #if !targetEnvironment(macCatalyst)
                        if UIDevice.current.userInterfaceIdiom == .pad, isPresented {
                            Button {
                                router?.inspectorSheet = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                        }
                        #endif

                        VStack(alignment: .leading) {
                            Text("Queue")
                                .bold()
                            Text(tracks.count, format: .number)
                                .contentTransition(.numericText())
                                .foregroundStyle(.secondary)
                        }
                    }

                    ToolbarItemGroup(placement: .topBarTrailing) {
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
                                try? await Task.sleep(for: .milliseconds(200))
                                withAnimation {
                                    proxy.scrollTo(group.coordinatorRoom.track.id)
                                }
                            }
                        } label: {
                            Image(systemName: "shuffle")
                                .foregroundStyle(group.playMode.contains(.shuffle) ? .accent : .secondary)
                                .contentTransition(.symbolEffect(.automatic))
                        }

                        Button {
                            var currentPlayMode = group.playMode

                            if currentPlayMode.contains(.normal) || currentPlayMode.rawValue == 1 {
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
                                .foregroundStyle(group.playMode.rawValue > 2 ? .accent : .secondary)
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
                }.task(id: group) {
                    isLoading = true
                    self.tracks = await sonosService.getQueue(ip: group.ip)
                    group.playMode = await sonosService.playMode(ip: group.ip)
                    isLoading = false
                    withAnimation {
                        proxy.scrollTo(group.coordinatorRoom.track.id)
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
        .overlay(alignment: .bottom) {
            if group.playbackService != .queue  {
                Text("Queue Not Active")
                    .padding()
                    .background(.thickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .fontDesign(.rounded)
        .animation(.default, value: group.playbackService)
    }

    private func move(from source: IndexSet, to destination: Int) {
        // TODO: Fix swap positions
        tracks.move(fromOffsets: source, toOffset: destination)

        Task {
            guard let sourceIndex = source.first else { return }
            try await sonosService.reorderQueue(group, from: sourceIndex + 1, to: destination + 1)
        }
    }

    private func isTrackPlaying(for track: Track) -> Bool {
        group.coordinatorRoom.track.position == track.position && group.playbackService == .queue
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
