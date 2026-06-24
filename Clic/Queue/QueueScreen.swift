import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI
import Collections
import Defaults

struct QueueScreen: View {
    @Environment(PlayHistoryService.self) var playHistoryService
    @AppStorage(AppStorageKeys.queueMode) private var queueMode: QueueMode = .upNext

    var group: GroupRoom
    var closeInspector: (() -> Void)? = nil
    
    @State private var editMode: EditMode = .inactive
    @State private var router = Router()
    @State private var isLoading: Bool = false
    @State private var selectedGroupService = SelectedGroupService()
    // First-load scroll sentinel: empty means we haven't scrolled to now-playing for this
    // group yet (so the initial scroll is unanimated). The now-playing highlight no longer
    // uses this — it compares queue position directly.
    @State private var currentTrackID: String = ""
    @State private var currentGroupIP: String = ""
    @State private var selection: Set<String> = []
    @State private var upNextTracks: [PlayableContent] = []
    
    var body: some View {
//        let _ = Self._printChanges()
        NavigationStack(path: $router.path) {
            ScrollViewReader { proxy in
                VStack {
                    if queueMode == .full {
                        fullQueueView(proxy: proxy)
                    } else {
                        UpNextContentView(editMode: $editMode, group: group, router: router, selection: $selection, upNext: $upNextTracks)
                    }
                }
                .withSheetDestinations(sheetDestinations: $router.presentedSheet, onDismiss: {
                    Task {
                        group.coordinatorRoom.queue = OrderedSet(await SonosService.shared.getQueue(ip: group.ip))
                    }
                })
                .withAppRouter()
                .saturation(group.playbackService == .queue ? 1 : 0.1 )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .principal) {
                        VStack(alignment: .leading) {
                            HStack(spacing: 4) {
                                Text(queueMode.title)
                                if group.playbackService == .queue {
                                    if queueMode == .full {
                                        Text("(\(group.coordinatorRoom.queueTotal, format: .number))")
                                            .contentTransition(.numericText())
                                            .monospacedDigit()
                                    }
                                } else {
                                    Text("not active")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .bold()
                            if queueMode == .full, totalDuration.components.seconds > 0 {
                                Text(totalDuration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                                if queueMode == .full {
                                    // Rows are keyed by a reorder-stable occurrence key, so simply
                                    // swapping in the new order animates rows sliding into place.
                                    let newQueue = await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip)
                                    withAnimation(.easeInOut(duration: shuffleAnimationDuration)) {
                                        group.coordinatorRoom.queue = OrderedSet(newQueue)
                                    }
                                    try? await SonosService.shared.updateTrackInformation(for: [group])
                                    currentTrackID = group.coordinatorRoom.track.toPlayable.trackID
                                    try? await Task.sleep(for: .milliseconds(50))
                                    scrollToNowPlayingRow(proxy)
                                } else {
                                    let position = await SonosService.shared.getTrack(ip: group.coordinatorRoom.ip)?.position ?? 0
                                    let newTracks = await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip, with: position, total: 50)
                                    withAnimation(.easeInOut(duration: shuffleAnimationDuration)) {
                                        upNextTracks = newTracks
                                    }
                                }
                            }
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(group.playMode.contains(.shuffle) ? .accent : .secondary)
                                .contentTransition(.symbolEffect(.automatic))
                        }
                        
                        Button {
                            var currentPlayMode = group.playMode
                            
                            if currentPlayMode.contains(.normal) && !currentPlayMode.isRepeatEnabled {
                                currentPlayMode.remove(.normal)
                                currentPlayMode.insert(.repeatAll)
                            } else if currentPlayMode.isRepeatAllEnabled {
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
                                try? await SonosService.shared.updateTrackInformation(for: [group])
                                currentTrackID = group.coordinatorRoom.track.toPlayable.trackID
                                try? await Task.sleep(for: .milliseconds(50))
                                scrollToNowPlayingRow(proxy)
                            }
                        } label: {
                            Label("Repeat", systemImage: group.playMode.contains(.repeatOne) ? "repeat.1" : "repeat")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(group.playMode.isRepeatEnabled ? .accent : .secondary)
                                .contentTransition(.symbolEffect(.automatic))
                        }
                        
                        QueueMoreInfoView(group: group, router: router, editMode: $editMode, queueMode: $queueMode, upNextTracks: $upNextTracks)
                            .contentTransition(.identity)
                    }
                }
            }
        }
        .overlay {
            if isLoading, group.coordinatorRoom.queue.isEmpty {
                ProgressView()
            }
        }
        .fontDesign(.rounded)
        .environment(router)
        .environment(selectedGroupService)
        .onAppear {
            selectedGroupService.group = group
            Task {
                if let playbackService = await SonosService.shared.playbackService(ip: group.ip) {
                    group.playbackService = playbackService
                }
                // Sync the shuffle/repeat state for both modes; the full-queue view's
                // task only runs when that mode is visible, leaving Up Next stale.
                group.playMode = await SonosService.shared.playMode(ip: group.ip)
            }
        }
        .overlay {
            VStack {
                Button { closeInspector?() } label: { EmptyView() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                } label: { EmptyView() }
                    .keyboardShortcut("e", modifiers: [])
            }
            .frame(width: 0, height: 0)
            .accessibility(hidden: true)
            .hidden()
        }
        .safeArea(edge: .bottom) {
            if !selection.isEmpty {
                HStack {
                    Button {
                        
                            selection.removeAll()
                        
                    } label: {
                        Label("Deselect All", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .foregroundStyle(Color(UIColor.systemBackground))
                    .tint(Color(UIColor.label))

                    Button(role: .destructive) {
                        Task {
                            if queueMode == .full {
                                await deleteFullQueueTracks(selection)
                            } else {
                                await deleteUpNextTracks(selection)
                            }
                        }
                    } label: {
                        Text("Remove \(selection.count) Tracks")
                            .monospacedDigit()
                    }
                    .buttonStyle(.bordered)
                    
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.interactiveSpring, value: selection)
    }
    
    @ViewBuilder
    private func fullQueueView(proxy: ScrollViewProxy) -> some View {
        List(selection: $selection) {
            ForEach(Array(group.coordinatorRoom.queue.keyedByOccurrence().enumerated()), id: \.element.key) { index, keyed in
                let track = keyed.track
                HStack(spacing: 0) {
                    Text(formatPosition(index + 1))
                        .font(.caption.monospacedDigit().smallCaps())
                        .foregroundStyle(track.metadata?.position == group.coordinatorRoom.track.position ? .primary : .secondary)
                        .frame(width: positionWidth, alignment: .trailing)
                        .padding(.trailing, 8)
                    QueueCellView(track: track, group: group, router: router, isEditing: editMode.isEditing, onLocalMoveNext: handleLocalMoveNext, onLocalDelete: handleLocalDelete)
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden, edges: .all)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
            .onMove(perform: move)
        }
        .tint(.accentColor.opacity(0.5))
        .contextMenu(forSelectionType: String.self) { selectedKeys in
            let tracks = group.coordinatorRoom.queue.tracks(forKeys: selectedKeys)
            if tracks.first?.content.service != .unknown {
                if selectedKeys.count == 1, let track = tracks.first {
                    AddToPlaylistMenu(itemToAdd: track)

                    Button {
                        router.navigate(to: .mediaDetail(content: track, group: group))
                    } label: { Label("View Album", systemImage: "smallcircle.filled.circle.fill") }

                    Button {
                        router.navigate(to: .artistDetail(content: track, group: group))
                    } label: { Label("View Artist", systemImage: "music.mic") }

                    Button {
                        handleLocalMoveNext(track)
                        Task {
                            guard let position = track.metadata?.position else { return }
                            let nextPosition = group.coordinatorRoom.track.position + 1
                            guard position != nextPosition else { return }
                            try? await SonosService.shared.reorderQueue(group, from: position, to: nextPosition)
                        }
                    } label: {
                        Text("Play Next")
                        Text("After \(group.coordinatorRoom.track.name)")
                        Image(systemName: "text.insert")
                    }
                } else {
                    AddTracksToPlaylistMenu(tracks: tracks)
                }
            }
            Button(role: .destructive) {
                Task { await deleteFullQueueTracks(selectedKeys) }
            } label: {
                Label(selectedKeys.count == 1 ? "Remove" : "Remove \(selectedKeys.count) Tracks", systemImage: "xmark")
            }
        }
        .environment(\.editMode, $editMode)
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
        .task(id: group.coordinatorRoom.track.trackID) {
            if group.ip != currentGroupIP {
                currentTrackID = ""
                currentGroupIP = group.ip
            }
            isLoading = true
            await scrollToNowPlaying(proxy)
            group.playMode = await SonosService.shared.playMode(ip: group.ip)
            isLoading = false
        }
    }
    
    private func handleLocalMoveNext(_ track: PlayableContent) {
        guard let fromIndex = group.coordinatorRoom.queue.firstIndex(where: { $0.trackID == track.trackID }) else { return }
        let currentPosition = group.coordinatorRoom.track.position
        // position is 1-indexed, so currentPosition is the 0-based index of the "next" slot
        let targetIndex = min(currentPosition, group.coordinatorRoom.queue.count - 1)
        guard fromIndex != targetIndex else { return }
        var updated = Array(group.coordinatorRoom.queue)
        let item = updated.remove(at: fromIndex)
        let insertAt = fromIndex < targetIndex ? targetIndex - 1 : targetIndex
        updated.insert(item, at: insertAt)
        withAnimation {
            group.coordinatorRoom.queue = OrderedSet(updated)
        }
    }

    private func handleLocalDelete(_ track: PlayableContent) {
        group.coordinatorRoom.queue.removeAll { $0.trackID == track.trackID }
        
        Task {
            try await Task.sleep(for: .milliseconds(200))
            guard let position = track.metadata?.position else { return }
            
            for index in group.coordinatorRoom.queue.indices {
                if let currentPosition =  group.coordinatorRoom.queue[index].metadata?.position, currentPosition >= position {
                    var currentItem = group.coordinatorRoom.queue[index]
                    group.coordinatorRoom.queue.remove(currentItem)
                    currentItem.metadata?.position = currentPosition - 1
                    group.coordinatorRoom.queue.insert(currentItem, at: index)
                }
            }
            try? await SonosService.shared.updateTrackInformation(for: [group])
            let id = group.coordinatorRoom.track.toPlayable.trackID
            currentTrackID = id
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }
        group.coordinatorRoom.queue.elements.move(fromOffsets: source, toOffset: destination)
        Task {
            try? await SonosService.shared.reorderQueue(group, from: sourceIndex + 1, to: destination + 1)
        }
    }

    private let shuffleAnimationDuration: TimeInterval = 0.35

    /// Scrolls the full queue to the now-playing row. Rows are identified by their occurrence
    /// key, so the scroll target has to be resolved the same way rather than from `trackID`.
    private func scrollToNowPlayingRow(_ proxy: ScrollViewProxy, anchor: UnitPoint? = nil) {
        guard let key = group.coordinatorRoom.queue.occurrenceKey(forPosition: group.coordinatorRoom.track.position) else { return }
        withAnimation {
            proxy.scrollTo(key, anchor: anchor)
        }
    }

    private var totalDuration: Duration {
        Duration.seconds(group.coordinatorRoom.queue.compactMap(\.metadata?.duration?.components.seconds).reduce(Int64.zero, +))
    }

    private func formatPosition(_ position: Int) -> String {
        if position >= 1000 {
            let thousands = Double(position) / 1000.0
            return String(format: "%.1fK", thousands)
        }
        return "\(position)"
    }

    private var positionWidth: CGFloat {
        let maxPosition = group.coordinatorRoom.queueTotal
        if maxPosition >= 1000 {
            return 35
        } else if maxPosition >= 100 {
            return 28
        } else {
            return 20
        }
    }

    private func deleteFullQueueTracks(_ selectedKeys: Set<String>) async {
        let selectedTracks = group.coordinatorRoom.queue.tracks(forKeys: selectedKeys)
        let sortedTracks = selectedTracks.sorted { ($0.metadata?.position ?? 0) > ($1.metadata?.position ?? 0) }
        withAnimation {
            for track in sortedTracks {
                group.coordinatorRoom.queue.removeAll { $0.trackID == track.trackID }
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard let position = sortedTracks.last?.metadata?.position else { return }
            for index in group.coordinatorRoom.queue.indices {
                guard let currentPosition = group.coordinatorRoom.queue[index].metadata?.position, currentPosition >= position else { continue }
                var item = group.coordinatorRoom.queue[index]
                group.coordinatorRoom.queue.remove(item)
                item.metadata?.position = currentPosition - sortedTracks.count
                group.coordinatorRoom.queue.insert(item, at: index)
            }
            try? await SonosService.shared.updateTrackInformation(for: [group])
            currentTrackID = group.coordinatorRoom.track.toPlayable.trackID
        }
        for track in sortedTracks {
            guard let position = track.metadata?.position else { continue }
            try? await SonosService.shared.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
        }
        group.coordinatorRoom.queueTotal = (try? await SonosService.shared.getQueueTotal(group: group)) ?? 0
        selection.removeAll()
    }

    private func deleteUpNextTracks(_ selectedKeys: Set<String>) async {
        let selectedTracks = upNextTracks.tracks(forKeys: selectedKeys)
        let sortedTracks = selectedTracks.sorted { ($0.metadata?.position ?? 0) > ($1.metadata?.position ?? 0) }
        withAnimation {
            for track in sortedTracks {
                upNextTracks.removeAll { $0.trackID == track.trackID }
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard let position = sortedTracks.last?.metadata?.position else { return }
            for index in upNextTracks.indices {
                if let currentPosition = upNextTracks[index].metadata?.position, currentPosition >= position {
                    upNextTracks[index].metadata?.position = currentPosition - sortedTracks.count
                }
            }
        }
        for track in sortedTracks {
            guard let position = track.metadata?.position else { continue }
            try? await SonosService.shared.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
        }
        group.coordinatorRoom.queueTotal = (try? await SonosService.shared.getQueueTotal(group: group)) ?? 0
        selection.removeAll()
    }

    private func scrollToNowPlaying(_ proxy: ScrollViewProxy) async {
        let queue = OrderedSet(await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip))
        if self.group.coordinatorRoom.queue != queue, !queue.isEmpty {
            self.group.coordinatorRoom.queue = queue
        }
        try? await Task.sleep(for: .milliseconds(10))
        if !currentTrackID.isEmpty {
            scrollToNowPlayingRow(proxy, anchor: .top)
        } else if let key = group.coordinatorRoom.queue.occurrenceKey(forPosition: group.coordinatorRoom.track.position) {
            proxy.scrollTo(key, anchor: .top)
        }
        currentTrackID = group.coordinatorRoom.track.toPlayable.trackID
    }
}

#Preview("Queue with History") {
    @Previewable var group = GroupRoom.garage
    
    Text("Queue...")
        .sheet(isPresented: .constant(true)) {
            QueueScreen(group: group)
                .presentationDetents([.medium, .large])
                .onAppear {
                    group.coordinatorRoom.queue = [
                        .init(title: "Bohemian Rhapsody", subtitle: "Queen", thumbnail: URL(string: "https://i.scdn.co/image/ab67616d00001e02e8b066f70c206551210d902b"), artwork: URL(string: "https://i.scdn.co/image/ab67616d0000b273e8b066f70c206551210d902b"), content: .init(service: .spotify, id: "3z8h0TU7ReDPLIbEnYhWZb", type: .track, location: nil)),
                        .init(title: "Shape of You", subtitle: "Ed Sheeran", thumbnail: URL(string: "https://i.scdn.co/image/ab67616d00001e02ba5db46f4b838ef6027e6f96"), artwork: URL(string: "https://i.scdn.co/image/ab67616d0000b273ba5db46f4b838ef6027e6f96"), content: .init(service: .spotify, id: "7qiZfU4dY1lWllzX7mPBI3", type: .track, location: nil)),
                        .init(title: "Blinding Lights", subtitle: "The Weeknd", thumbnail: URL(string: "https://i.scdn.co/image/ab67616d00001e02e6f407c7f3a0ec98845e4431"), artwork: URL(string: "https://i.scdn.co/image/ab67616d0000b273e6f407c7f3a0ec98845e4431"), content: .init(service: .spotify, id: "0VjIjW4GlUZAMYd2vXMi3b", type: .track, location: nil)),
                        .init(title: "Bad Guy", subtitle: "Billie Eilish", thumbnail: URL(string: "https://i.scdn.co/image/ab67616d00001e02847a57e3d2d6ea1f49b5f621"), artwork: URL(string: "https://i.scdn.co/image/ab67616d0000b273847a57e3d2d6ea1f49b5f621"), content: .init(service: .spotify, id: "2Fxmhks0bxGSBdJ92vM42m", type: .track, location: nil)),
                        .init(title: "Uptown Funk", subtitle: "Mark Ronson ft. Bruno Mars", thumbnail: URL(string: "https://i.scdn.co/image/ab67616d00001e02e7a385c0b9061386c084da87"), artwork: URL(string: "https://i.scdn.co/image/ab67616d0000b273e7a385c0b9061386c084da87"), content: .init(service: .spotify, id: "32OlwWuMpZ6b0aN2RZOeMS", type: .track, location: nil)),
                        .init(title: "Someone Like You", subtitle: "Adele", thumbnail: URL(string: "https://i.scdn.co/image/ab67616d00001e0248f5def6c9b22592e3e7c8ea"), artwork: URL(string: "https://i.scdn.co/image/ab67616d0000b27348f5def6c9b22592e3e7c8ea"), content: .init(service: .spotify, id: "1HNE2PX70ztbEl6MLxrpNL", type: .track, location: nil)),
                        .init(title: "Sweet Child O' Mine", subtitle: "Guns N' Roses", thumbnail: URL(string: "https://i.scdn.co/image/ab67616d00001e02e44963b8bb127552ac761873"), artwork: URL(string: "https://i.scdn.co/image/ab67616d0000b273e44963b8bb127552ac761873"), content: .init(service: .spotify, id: "7o2CTH4ctstm8TNelqjb51", type: .track, location: nil)),
                        .init(title: "Shake It Off", subtitle: "Taylor Swift", thumbnail: URL(string: "https://i.scdn.co/image/ab67616d00001e02e11a75a2f2ff39cec788c5e8"), artwork: URL(string: "https://i.scdn.co/image/ab67616d0000b273e11a75a2f2ff39cec788c5e8"), content: .init(service: .spotify, id: "0cqRj7pUJDkTCEsJkx8snD", type: .track, location: nil)),
                        .init(title: "Smells Like Teen Spirit", subtitle: "Nirvana", thumbnail: URL(string: "https://i.scdn.co/image/ab67616d00001e02e175a19e530c898d167d39bf"), artwork: URL(string: "https://i.scdn.co/image/ab67616d0000b273e175a19e530c898d167d39bf"), content: .init(service: .spotify, id: "5ghIJDpPoe3CfHMGu71E6T", type: .track, location: nil)),
                        .init(title: "Billie Jean", subtitle: "Michael Jackson", thumbnail: URL(string: "https://i.scdn.co/image/ab67616d00001e02de437d960dda1ac0a3586d97"), artwork: URL(string: "https://i.scdn.co/image/ab67616d0000b273de437d960dda1ac0a3586d97"), content: .init(service: .spotify, id: "5ChkMS8OtdzJeqyybCc9R5", type: .track, location: nil))
                    ]
//                    group.coordinatorRoom.queue = PlayHistoryService.shared.history
                }
        }
        .environment(PlayHistoryService.shared)
        .withEnvironments()
}

#Preview("Queue Empty") {
    Text("Queue...")
        .sheet(isPresented: .constant(true)) {
            QueueScreen(group: .garage)
                .presentationDetents([.medium, .large])
        }
        .environment(PlayHistoryService.shared)
        .withEnvironments()

}
