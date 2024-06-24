import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI

struct QueueScreen: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.isPresented) var isPresented
    @Environment(SonosService.self) var sonosService: SonosService

    @Binding var group: GroupRoom
    @State private var router = Router()
    @State private var tracks: [PlayableContent] = []
    @State private var isLoading: Bool = true
    @State private var clearQueueConfirmation: Bool = false
    @State private var playlists: [PlayableContent] = []

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(tracks, id: \.trackID) { track in
                        Button {
                            dismiss()
                            Task {
                                HapticManager.shared.fireHaptic(.buttonPress)
                                guard let position = track.metadata?.position else { return }
                                await sonosService.seek(trackNumber: position, on: group)
                                await sonosService.play(ip: group.coordinatorRoom.ip)
                            }
                        } label: {
                            HStack {
                                ContentArtworkView(content: track)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 60, height: 60)
                                VStack(alignment: .leading) {
                                    Text(track.title)
                                        .lineLimit(1)
                                    Text(track.subtitle)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    if let duration = track.metadata?.duration, duration.components.seconds != 0 {
                                        Text(duration, format: .time(pattern: .minuteSecond))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                Menu {
                                    menu(content: track)
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .frame(maxWidth: 40, maxHeight: .infinity, alignment: .trailing)
                                        .background(.clear)
                                        .tint(.primary)
                                        .bold()
                                }
                            }
                            .contextMenu {
                                menu(content: track)
                            }
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
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowBackground(isTrackPlaying(for: track) ? Color(uiColor: UIColor.systemFill) : Color.clear)
                        .bold(isTrackPlaying(for: track))
                        .draggable(track)
                    }
                    .onMove(perform: move)
                }
                .withSheetDestinations(sheetDestinations: $router.presentedSheet, onDismiss: {
                    Task {
                        self.tracks = await sonosService.getQueue(ip: group.ip)
                    }
                })
                .saturation(group.playbackService == .queue ? 1 : 0.1 )
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
#if !targetEnvironment(macCatalyst)
                        if UIDevice.current.userInterfaceIdiom == .pad, isPresented {
                            Button {
                                //                                router?.inspectorSheet = nil
                                dismiss()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                        }
#endif

                        VStack(alignment: .leading) {
                            Text("Queue")
                                .bold()
                            HStack(spacing: 0) {
                                Text(tracks.count, format: .number)
                                    .contentTransition(.numericText())
                                Text("\(totalDuration.components.seconds > 0 ? " • " : "")")
                                if totalDuration.components.seconds > 0  {
                                    Text(totalDuration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                                }
                            }
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
                                    let id = group.coordinatorRoom.track.trackID + "\(group.coordinatorRoom.track.position)"
                                    proxy.scrollTo(id)
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

                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            Task {
                                router.presentedSheet = .newPlaylist(group: group)
                            }
                        } label: {
                            Text("Save")
                        }
                        .disabled(tracks.isEmpty)
                        Button(role: .destructive) {
                            clearQueueConfirmation.toggle()
                        } label: {
                            Text("Clear")
                        }
                        .disabled(tracks.isEmpty)
                    }
                }.task(id: group) {
                    isLoading = true
                    self.tracks = await sonosService.getQueue(ip: group.ip)
                    group.playMode = await sonosService.playMode(ip: group.ip)
                    isLoading = false
                    withAnimation {
                        let id = group.coordinatorRoom.track.trackID + "\(group.coordinatorRoom.track.position)"
                        proxy.scrollTo(id)
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
        .confirmationDialog("Clear Queue", isPresented: $clearQueueConfirmation, titleVisibility: .hidden) {
            Button {
                Task {
                    try await sonosService.clearQueue(group.coordinatorRoom.ip)
                    tracks = await sonosService.getQueue(ip: group.coordinatorRoom.ip)
                }
            } label: {
                Text("Clear Queue")
                    .bold()
            }
        }
        .environment(router)
        .task {
            playlists = await sonosService.sonosPlaylists()
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        // TODO: Fix swap positions
        tracks.move(fromOffsets: source, toOffset: destination)
        guard let sourceIndex = source.first else { return }

        Task {
            try await sonosService.reorderQueue(group, from: sourceIndex + 1, to: destination + 1)
            tracks = await sonosService.getQueue(ip: group.coordinatorRoom.ip)
        }
    }

    private func isTrackPlaying(for song: PlayableContent) -> Bool {
        guard let position = song.metadata?.position else { return false }
        return group.coordinatorRoom.track.position == position && group.playbackService == .queue
    }

    private var totalDuration: Duration {
        Duration.seconds(tracks.compactMap(\.metadata?.duration?.components.seconds).reduce(Int64.zero, +))
    }

    @MainActor
    private func menu(content: PlayableContent) -> some View {
        VStack {
            if content.content.service != .unknown {
                AddToPlaylistMenu(itemToAdd: content)

                Button {
                    router.sheet(to: .mediaDetail(content: content, group: group))
                } label: {
                    Label("View Album", systemImage: "smallcircle.circle.fill")
                }

                Button {
                    router.sheet(to: .artistDetail(content: content, group: group))
                } label: {
                    Label("View Artist", systemImage: "music.mic")
                }
            }
            //                let playable = group.coordinatorRoom.track.toPlayable
            //                ShareLink(item: playable)

            Button(role: .destructive) {
                guard let position = content.metadata?.position else { return }
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
