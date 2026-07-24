import SwiftUI
import MusicSearchKit
import SonosKit
import OrderedCollections

struct UpNextContentView: View {
    @Environment(PlayHistoryService.self) var playHistoryService
    @Binding var editMode: EditMode

    var group: GroupRoom
    var router: Router
    @Binding var selection: Set<String>
    @Binding var upNext: [PlayableContent]

    @State private var isLoading: Bool = false
    @State private var hasLoaded: Bool = false
    @State private var isPaginating: Bool = true
    @State private var currentStartingIndex: Int = 0
    @State private var pageSize: Int = 50

    private var startPosition: Int { group.coordinatorRoom.track.position }
    private var paginationThreshold: Int { upNext.count - 30 }

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(Array(upNext.keyedByOccurrence().enumerated()), id: \.element.key) { index, keyed in
                    let track = keyed.track
                    HStack(spacing: 0) {
                        Text(formatPosition(startPosition + index + 1))
                            .font(.caption.monospacedDigit().smallCaps())
                            .foregroundStyle(.secondary)
                            .frame(width: positionWidth, alignment: .trailing)
                            .padding(.trailing, 8)
                        QueueCellView(track: track, group: group, router: router, isEditing: editMode.isEditing, onLocalMoveNext: handleLocalMoveNext, onLocalDelete: handleLocalDelete)
                    }
                    .listRowSeparator(.hidden)
                    .listSectionSeparator(.hidden, edges: .all)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .onAppear {
                        guard index >= paginationThreshold,
                              !isPaginating,
                              !isLoading,
                              upNext.count >= 20 else { return }
                        Task { await loadMoreTracks() }
                    }
                }
                .onMove(perform: move)
                
                if upNext.isEmpty, !isLoading {
                    ContentUnavailableView("Nothing up next", systemImage: "music.note.list")
                        .transition(.opacity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                // Fixed-height spacer prevents layout shift during pagination
                if hasMoreTracks() {
                    Color.clear
                        .frame(height: 44)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .overlay {
                            if isPaginating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                }
            }
            .listStyle(.plain)
            // Breathing room so the last row clears the bottom selection bar and stays tappable.
            .contentMargins(.bottom, 16, for: .scrollContent)
            .tint(.accentColor.opacity(0.5))
            .contextMenu(forSelectionType: String.self) { selectedKeys in
                let tracks = upNext.tracks(forKeys: selectedKeys)
                if tracks.first?.content.service != .unknown {
                    if selectedKeys.count == 1, let track = tracks.first {
                        AddToLastPlaylistButton(itemToAdd: track)
                        Button {
                            router.sheet(to: .addToPlaylist(content: track))
                        } label: { Label("Add to Playlist…", systemImage: "text.badge.plus") }

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
                    Task { await deleteSelected(selectedKeys) }
                } label: {
                    Label(selectedKeys.count == 1 ? "Remove" : "Remove \(selectedKeys.count) Tracks", systemImage: "trash")
                }
            }
            .environment(\.editMode, $editMode)
            .task(id: group.coordinatorRoom.track.trackID) {
                await loadUpNext()
            }
            .overlay {
                if isLoading, upNext.isEmpty {
                    ProgressView()
                }
            }
        }
    }
    
    private func loadUpNext() async {
        isLoading = true
        isPaginating = false
        currentStartingIndex = group.coordinatorRoom.track.position
        let tracks = await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip, with: currentStartingIndex, total: pageSize)
        if hasLoaded {
            withAnimation(.easeInOut(duration: 0.25)) {
                upNext = tracks
                isLoading = false
            }
        } else {
            upNext = tracks
            isLoading = false
            hasLoaded = true
        }
        // Keep the last known total on a failed fetch — zeroing it makes the
        // queue toolbar gauge read as full/empty until the next refresh.
        if let total = try? await SonosService.shared.getQueueTotal(group: group) {
            group.coordinatorRoom.queueTotal = total
        }
    }
    
    private func hasMoreTracks() -> Bool {
        guard group.coordinatorRoom.queueTotal > 0 else { return false }
        let nextStartingIndex = currentStartingIndex + upNext.count
        return nextStartingIndex < group.coordinatorRoom.queueTotal
    }
    
    private func loadMoreTracks() async {
        guard hasMoreTracks() && !isPaginating else { return }

        isPaginating = true
        let nextStartingIndex = currentStartingIndex + upNext.count
        let nextBatch = await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip, with: nextStartingIndex, total: pageSize)

        // Append without animation to prevent scroll interruption on Catalyst
        withAnimation(nil) {
            upNext.append(contentsOf: nextBatch)
            isPaginating = false
        }
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
            return 35 // Fixed width for "1.0K" format
        } else if maxPosition >= 100 {
            return 28 // Width for 3 digits
        } else {
            return 20 // Width for 1-2 digits
        }
    }
    
    private func deleteSelected(_ selectedKeys: Set<String>) async {
        let selectedTracks = upNext.tracks(forKeys: selectedKeys)
        let sortedTracks = selectedTracks.sorted { ($0.metadata?.position ?? 0) > ($1.metadata?.position ?? 0) }
        withAnimation {
            for track in sortedTracks {
                upNext.removeAll { $0.trackID == track.trackID }
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard let position = sortedTracks.last?.metadata?.position else { return }
            for index in upNext.indices {
                if let currentPosition = upNext[index].metadata?.position, currentPosition >= position {
                    upNext[index].metadata?.position = currentPosition - sortedTracks.count
                }
            }
        }
        for track in sortedTracks {
            guard let position = track.metadata?.position else { continue }
            try? await SonosService.shared.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
        }
        // Keep the last known total on a failed fetch — zeroing it makes the
        // queue toolbar gauge read as full/empty until the next refresh.
        if let total = try? await SonosService.shared.getQueueTotal(group: group) {
            group.coordinatorRoom.queueTotal = total
        }
        selection.removeAll()
    }
    
    private func handleLocalMoveNext(_ track: PlayableContent) {
        guard let fromIndex = upNext.firstIndex(where: { $0.trackID == track.trackID }) else { return }
        guard fromIndex != 0 else { return }
        withAnimation {
            let item = upNext.remove(at: fromIndex)
            upNext.insert(item, at: 0)
        }
    }

    private func handleLocalDelete(_ track: PlayableContent) {
        upNext.removeAll { $0.trackID == track.trackID }
        
        Task {
            try await Task.sleep(for: .milliseconds(200))
            guard let position = track.metadata?.position else { return }
            
            for index in upNext.indices {
                if let currentPosition = upNext[index].metadata?.position, currentPosition >= position {
                    upNext[index].metadata?.position = currentPosition - 1
                }
            }
        }
    }
    
    private func move(from source: IndexSet, to destination: Int) {
        let sourceTrack = upNext[source.first ?? 0]
        let destinationTrack = destination < upNext.count ? upNext[destination] : upNext.last
        guard let actualSourcePosition = sourceTrack.metadata?.position,
              let actualDestinationPosition = destinationTrack?.metadata?.position else { return }
        upNext.move(fromOffsets: source, toOffset: destination)
        Task {
            try? await SonosService.shared.reorderQueue(group, from: actualSourcePosition, to: actualDestinationPosition)
        }
    }
}
