import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI
import Collections

struct QueueScreen: View {
    @Environment(\.dismiss) var dismiss
    @Environment(SonosService.self) var sonosService: SonosService
    var closeInspector: (() -> Void)? = nil
    @Binding var group: GroupRoom
    @State private var router = Router()
    @State private var isLoading: Bool = true
    @State private var clearQueueConfirmation: Bool = false
    @State private var selectedGroupService = SelectedGroupService()

    var body: some View {
        NavigationStack(path: $router.path) {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(group.coordinatorRoom.queue), id: \.trackID) { track in
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
                                }
                                Spacer()
                                Menu {
                                    menu(content: track)
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .frame(maxWidth: 50, maxHeight: .infinity)
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
                                group.coordinatorRoom.queue.remove(at: position - 1)
                                Task {
                                    try? await sonosService.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
                                    group.coordinatorRoom.queue =  OrderedSet(await sonosService.getQueue(ip: group.ip))
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowBackground(isTrackPlaying(for: track) ? Color(uiColor: UIColor.systemFill) : Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 0))
                        .bold(isTrackPlaying(for: track))
                        .draggable(track)
                    }
                    .onMove(perform: move)
                }
                .withSheetDestinations(sheetDestinations: $router.presentedSheet, onDismiss: {
                    Task {
                        group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.ip))
                    }
                })
                .withAppRouter(router: router)
                .saturation(group.playbackService == .queue ? 1 : 0.1 )
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        VStack(alignment: .leading) {
                            Text("Queue")
                                .bold()
                            HStack(spacing: 0) {
                                Text(group.coordinatorRoom.queue.count, format: .number)
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
                                group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.coordinatorRoom.ip))
                                try? await Task.sleep(for: .milliseconds(100))
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
                                group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.coordinatorRoom.ip))
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
                        .disabled(group.coordinatorRoom.queue.isEmpty)

                        Button(role: .destructive) {
                            clearQueueConfirmation.toggle()
                        } label: {
                            Text("Clear")
                        }
                        .disabled(group.coordinatorRoom.queue.isEmpty)
                    }
                }
                .task(id: group.coordinatorRoom.track.trackID) {
                    isLoading = true
                    group.playMode = await sonosService.playMode(ip: group.ip)
                    let id = group.coordinatorRoom.track.trackID + "\(group.coordinatorRoom.track.position)"
                    proxy.scrollTo(id)
                    self.group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.coordinatorRoom.ip))
                    isLoading = false
                }
                .animation(.spring, value: group.coordinatorRoom.queue)
                .addDismiss {
                    dismiss()
                    closeInspector?()
                }
            }
        }
        .presentationBackground(.thinMaterial)
        .overlay {
            if isLoading, group.coordinatorRoom.queue.isEmpty {
                ProgressView()
            }
            if group.coordinatorRoom.queue.isEmpty, !isLoading {
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
                    group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.coordinatorRoom.ip))
                }
            } label: {
                Text("Clear Queue")
                    .bold()
            }
        }
        .environment(router)
        .environment(selectedGroupService)
        .onAppear {
            selectedGroupService.group = group
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        // TODO: Fix swap positions
        group.coordinatorRoom.queue.elements.move(fromOffsets: source, toOffset: destination)
        guard let sourceIndex = source.first else { return }

        Task {
            try await sonosService.reorderQueue(group, from: sourceIndex + 1, to: destination + 1)
            group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.coordinatorRoom.ip))
        }
    }

    private func isTrackPlaying(for song: PlayableContent) -> Bool {
        guard let position = song.metadata?.position else { return false }
        return group.coordinatorRoom.track.position == position && group.playbackService == .queue
    }

    private var totalDuration: Duration {
        Duration.seconds(group.coordinatorRoom.queue.compactMap(\.metadata?.duration?.components.seconds).reduce(Int64.zero, +))
    }

    @MainActor
    private func menu(content: PlayableContent) -> some View {
        VStack {
            if content.content.service != .unknown {
                AddToPlaylistMenu(itemToAdd: content)

                Button {
                    router.navigate(to: .mediaDetail(content: content, group: group))
                } label: {
                    Label("View Album", systemImage: "smallcircle.circle.fill")
                }

                Button {
                    router.navigate(to: .artistDetail(content: content, group: group))
                } label: {
                    Label("View Artist", systemImage: "music.mic")
                }
            }

            Button(role: .destructive) {
                guard let position = content.metadata?.position else { return }
                group.coordinatorRoom.queue.remove(at: position - 1)
                Task {
                    try? await sonosService.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
                    group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.coordinatorRoom.ip))
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
