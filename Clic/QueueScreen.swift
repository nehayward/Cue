import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI
import Collections

struct QueueScreen: View {
    @Environment(PlayHistoryService.self) var playHistoryService
    
    var closeInspector: (() -> Void)? = nil
    
    @Binding var group: GroupRoom
    @State private var router = Router()
    @State private var isLoading: Bool = true
    @State private var clearQueueConfirmation: Bool = false
    @State private var selectedGroupService = SelectedGroupService()
    @State private var hoveredTrackID: String = ""
    @State private var currentTrackID: String = ""
    
    private var isCatalyst: Bool {
#if targetEnvironment(macCatalyst)
        return true
#endif
        return UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
//        let _ = Self._printChanges()

        NavigationStack(path: $router.path) {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(group.coordinatorRoom.queue), id: \.trackID) { track in
                        QueueCellView(track: track, group: group, currentTrackID: currentTrackID, router: router)
                            .listSectionSeparator(.hidden, edges: .all)
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(hoveredTrackID == track.trackID ? Color(uiColor: UIColor.tertiarySystemFill) : Color.clear)
                                    .padding(.horizontal, 4)
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 0))
                            .onHover { hovering in
                                if isCatalyst {
                                    hoveredTrackID = track.trackID
                                }
                                if !hovering {
                                    hoveredTrackID = ""
                                }
                            }
                            
                    }
                    .onMove(perform: move)
                }
                .withSheetDestinations(sheetDestinations: $router.presentedSheet, onDismiss: {
                    Task {
                        group.coordinatorRoom.queue = OrderedSet(await SonosService.shared.getQueue(ip: group.ip))
                    }
                })
                .withAppRouter()
                .saturation(group.playbackService == .queue ? 1 : 0.1 )
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .overlay {
                    if !isLoading, group.coordinatorRoom.queue.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 16) {
                            ForEach(playHistoryService.history.prefix(6)) { item in
                                PlayableCardView(item: item, hideAction: true)
                                    .frame(width: 120, height: 120)
                            }
                            .fontDesign(.rounded)
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        VStack(alignment: .leading) {
                            Text("Queue" + (group.playbackService != .queue ? " not active" : ""))
                                .bold()
                            HStack(spacing: 0) {
                                Text(group.coordinatorRoom.queueTotal, format: .number)
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
                                await SonosService.shared.setPlayMode(group.ip, mode: currentPlayMode)
                                group.coordinatorRoom.queue = OrderedSet(await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip))
                                try? await Task.sleep(for: .milliseconds(500))
                                withAnimation {
                                    let id = group.coordinatorRoom.track.toPlayable.trackID
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
                                await SonosService.shared.setPlayMode(group.ip, mode: currentPlayMode)
                                group.coordinatorRoom.queue = OrderedSet(await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip))
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
                        Spacer()
                        Button {
                            HapticManager.shared.fireHaptic(.buttonPress)
                            Router.main.presentedSheet = .search(group: group)
                        } label: {
                            Label("Search", systemImage: "magnifyingglass")
                                .fontDesign(.rounded)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            clearQueueConfirmation.toggle()
                        } label: {
                            Text("Clear")
                        }
                        .disabled(group.coordinatorRoom.queue.isEmpty)
                    }
                }
                .task(id: group.coordinatorRoom.track.trackID) {
                    let trackID: String = "\(group.coordinatorRoom.track.trackID).\(group.coordinatorRoom.track.position.description)"
                    currentTrackID = trackID
                    await scrollToNowPlaying(proxy)
                    group.playMode = await SonosService.shared.playMode(ip: group.ip)
                    isLoading = false
                }
#if !targetEnvironment(macCatalyst)
                .addDismiss {
                    router.presentedSheet = nil
                    closeInspector?()
                }
#endif
            }
        }
        .presentationBackground(.thinMaterial)
        .overlay {
            if isLoading, group.coordinatorRoom.queue.isEmpty {
                ProgressView()
            }
        }
        .fontDesign(.rounded)
        .animation(isCatalyst ? nil : .default, value: group.playbackService)
        .animation(isCatalyst ? nil : .spring, value: group.coordinatorRoom.queue)
        .animation(isCatalyst ? nil : .spring, value: isLoading)
        .confirmationDialog("Clear Queue", isPresented: $clearQueueConfirmation, titleVisibility: .hidden) {
            Button {
                Task {
                    try await SonosService.shared.clearQueue(group.coordinatorRoom.ip)
                    group.coordinatorRoom.queue = OrderedSet(await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip))
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
        .overlay(
            Button {
                closeInspector?()
            } label: {
                EmptyView()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .frame(width: 0, height: 0)
            .hidden()
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        // TODO: Fix swap positions
        group.coordinatorRoom.queue.elements.move(fromOffsets: source, toOffset: destination)
        guard let sourceIndex = source.first else { return }

        Task {
            try await SonosService.shared.reorderQueue(group, from: sourceIndex + 1, to: destination + 1)
            group.coordinatorRoom.queue = OrderedSet(await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip))
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
                    try? await SonosService.shared.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
                    group.coordinatorRoom.queueTotal = (try? await SonosService.shared.getQueueTotal(group: group)) ?? 0
                    group.coordinatorRoom.queue = OrderedSet(await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip))
                    
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
    
    private func scrollToNowPlaying(_ proxy: ScrollViewProxy) async {
        let id = group.coordinatorRoom.track.toPlayable.trackID
        let queue = OrderedSet(await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip))
        if self.group.coordinatorRoom.queue != queue, !queue.isEmpty {
            self.group.coordinatorRoom.queue = queue
        }
        try? await Task.sleep(for: .milliseconds(100))
        withAnimation {
            proxy.scrollTo(id, anchor: .top)
        }
    }
}

//fileprivate struct ContainerView: View {
//    @State var group: GroupRoom = .garage
//
//    var body: some View {
//        QueueScreen(group: $group)
//            .environment(SonosService.shared)
//            .presentationDetents([.medium, .large])
//    }
//}
//
//#Preview("Queue Garage") {
//    Text("Queue...")
//        .sheet(isPresented: .constant(true)) {
//            QueueScreen(group: .constant(.garage))
//                .environment(SonosService.shared)
//                .presentationDetents([.medium, .large])
//        }
//}

//#Preview {
//    Text("Queue...")
//        .sheet(isPresented: .constant(true)) {
//            ContainerView()
//        }
//}
