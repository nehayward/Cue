import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI
import Collections
import Defaults

enum QueueMode: String, CaseIterable {
    case full = "full"
    case upNext = "upNext"
    
    var title: String {
        switch self {
        case .full:
            return "Queue"
        case .upNext:
            return "Up Next"
        }
    }
    
    var icon: String {
        switch self {
        case .full:
            return "list.bullet"
        case .upNext:
            return "forward.fill"
        }
    }
}

struct QueueScreen: View {
    @Environment(PlayHistoryService.self) var playHistoryService
    @State private var editMode: EditMode = .inactive
    @AppStorage(AppStorageKeys.queueMode) private var queueMode: QueueMode = .upNext

    var group: GroupRoom
    var closeInspector: (() -> Void)? = nil
    
    @State private var router = Router()
    @State private var isLoading: Bool = false
    @State private var selectedGroupService = SelectedGroupService()
    @State private var currentTrackID: String = ""
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
                        UpNextContentView(editMode: $editMode, group: group, currentTrackID: currentTrackID, router: router, selection: $selection, upNext: $upNextTracks)
                            .listStyle(.plain)
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
                            Text("\(queueMode.title)" + (group.playbackService != .queue ? " not active" : ""))
                                .bold()
                            if queueMode == .full {
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
                                    group.coordinatorRoom.queue = OrderedSet(await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip))
                                    try? await SonosService.shared.updateTrackInformation(for: [group])
                                    let id = group.coordinatorRoom.track.toPlayable.trackID
                                    currentTrackID = id
                                    try? await Task.sleep(for: .milliseconds(50))
                                    withAnimation {
                                        proxy.scrollTo(id)
                                    }
                                } else {
                                    isLoading = true
                                    let position = await SonosService.shared.getTrack(ip: group.coordinatorRoom.ip)?.position ?? 0
                                    upNextTracks = await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip, with: position, total: 50)
                                    isLoading = false
                                }
                            }
                        } label: {
                            Image(systemName: "shuffle")
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
                                let id = group.coordinatorRoom.track.toPlayable.trackID
                                currentTrackID = id
                                try? await Task.sleep(for: .milliseconds(50))
                                withAnimation {
                                    proxy.scrollTo(id)
                                }
                            }
                        } label: {
                            Image(systemName: group.playMode.contains(.repeatOne) ? "repeat.1" : "repeat")
                                .foregroundStyle(group.playMode.isRepeatEnabled ? .accent : .secondary)
                                .contentTransition(.symbolEffect(.automatic))
                        }
                        
                        MoreInfoView(group: group, router: router, editMode: $editMode, queueMode: $queueMode)
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
            }
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
        .safeArea(edge: .bottom) {
            if !selection.isEmpty {
                Button(role: .destructive) {
                    Task {
                        // Get selected tracks from the appropriate source
                        let selectedTracks: [PlayableContent]
                        if queueMode == .full {
                            selectedTracks = selection.compactMap { trackID in
                                group.coordinatorRoom.queue.elements.first { $0.trackID == trackID }
                            }
                        } else {
                            selectedTracks = upNextTracks.filter { track in
                                selection.contains(track.trackID)
                            }
                        }
                        
                        // Sort by position (descending) to avoid index shifting issues
                        let sortedTracks = selectedTracks.sorted { track1, track2 in
                            (track1.metadata?.position ?? 0) > (track2.metadata?.position ?? 0)
                        }
                        
                        // Remove from local arrays first for immediate UI feedback
                        if queueMode == .upNext {
                            for track in sortedTracks {
                                upNextTracks.removeAll { $0.trackID == track.trackID }
                            }
                            // MARK: Update Track Position
                            Task {
                                try? await Task.sleep(for: .milliseconds(200))
                                guard let position = sortedTracks.last?.metadata?.position else { return }
                                for index in upNextTracks.indices {
                                    if let currentPosition = upNextTracks[index].metadata?.position, currentPosition >= position {
                                        upNextTracks[index].metadata?.position = currentPosition - sortedTracks.count
                                    }
                                }
                            }
                        } else {
                            for track in sortedTracks {
                                group.coordinatorRoom.queue.removeAll { $0.trackID == track.trackID }
                            }
                            
                            Task {
                                try? await Task.sleep(for: .milliseconds(200))
                                guard let position = sortedTracks.last?.metadata?.position else { return }
                                for index in group.coordinatorRoom.queue.indices {
                                    guard let currentPosition = group.coordinatorRoom.queue[index].metadata?.position, currentPosition >= position else { continue }
                                    var currentItem = group.coordinatorRoom.queue[index]
                                    group.coordinatorRoom.queue.remove(currentItem)
                                    currentItem.metadata?.position = currentPosition - sortedTracks.count
                                    group.coordinatorRoom.queue.insert(currentItem, at: index)
                                }
                                try? await SonosService.shared.updateTrackInformation(for: [group])
                                let id = group.coordinatorRoom.track.toPlayable.trackID
                                currentTrackID = id
                            }
                        }
                        
                        // Remove tracks using their actual queue positions
                        for track in sortedTracks {
                            guard let position = track.metadata?.position else { continue }
                            try? await SonosService.shared.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
                        }
                        
                        // Update queue total
                        group.coordinatorRoom.queueTotal = (try? await SonosService.shared.getQueueTotal(group: group)) ?? 0
                        
                        // Clear selection
                        selection.removeAll()
                    }
                } label: {
                    Text("Delete Selected (\(selection.count))")
                        .frame(maxWidth: .infinity)
                        .monospacedDigit()
                        .bold()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .offset(y: !selection.isEmpty ? 0 : 200)
#if targetEnvironment(macCatalyst)
                .padding(.bottom)
#endif
            }
        }
    }
    
    @ViewBuilder
    private func fullQueueView(proxy: ScrollViewProxy) -> some View {
        List(selection: $selection) {
            ForEach(Array(group.coordinatorRoom.queue.enumerated()), id: \.element.trackID) { index, track in
                HStack(spacing: 0) {
                    Text(formatPosition(index + 1))
                        .font(.caption.monospacedDigit().smallCaps())
                        .foregroundStyle(track.trackID == currentTrackID ? .primary : .secondary)
                        .frame(width: positionWidth, alignment: .trailing)
                        .padding(.trailing, 8)
                    QueueCellView(track: track, group: group, currentTrackID: currentTrackID, router: router, isEditing: editMode.isEditing, onLocalDelete: handleLocalDelete)
                }
                .listRowSeparator(.hidden)
                .listSectionSeparator(.hidden, edges: .all)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.clear)
                        .padding(.horizontal, 4)
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                #if targetEnvironment(macCatalyst)
                .contextMenu { menu(content: track) }
                #endif
            }
            .onMove(perform: move)
        }
        .environment(\.editMode, $editMode)
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
        .task(id: group.coordinatorRoom.track.trackID) {
            isLoading = true
            let id = group.coordinatorRoom.track.toPlayable.trackID
            currentTrackID = id
            await scrollToNowPlaying(proxy)
            group.playMode = await SonosService.shared.playMode(ip: group.ip)
            isLoading = false
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
        let queue = OrderedSet(await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip))
        if self.group.coordinatorRoom.queue != queue, !queue.isEmpty {
            self.group.coordinatorRoom.queue = queue
        }
        try? await Task.sleep(for: .milliseconds(10))
        let id = group.coordinatorRoom.track.toPlayable.trackID
        currentTrackID = id
        proxy.scrollTo(id, anchor: .top)
    }
}


fileprivate struct MoreInfoView: View {
    var group: GroupRoom
    var router: Router
    @Binding var editMode: EditMode
    @Binding var queueMode: QueueMode
    @State private var clearQueueConfirmation: Bool = false

    var body: some View {
        Menu {
            Button(editMode.isEditing ? "Done" : "Edit") {
                withAnimation {
                    editMode = editMode.isEditing ? .inactive : .active
                }
            }
            
            Button {
                queueMode = queueMode == .full ? .upNext : .full
            } label: {
                Label(queueMode == .full ? "Up Next" : "Queue", systemImage: queueMode == .full ? "text.insert" : "list.bullet")
            }
            Button {
                Task {
                    router.presentedSheet = .newPlaylist(group: group)
                }
            } label: {
                Text("Save Queue")
                Text("Create Sonos Playlist")
            }

            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                Router.main.presentedSheet = .search(group: group)
            } label: {
                Label("Search", systemImage: "magnifyingglass")
                    .fontDesign(.rounded)
            }
            Button(role: .destructive) {
                clearQueueConfirmation.toggle()
            } label: {
                Text("Clear Queue")
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(height: 44)
                .contentShape(.rect)
        }
        .help("Info")
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
        .tint(.primary)
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
