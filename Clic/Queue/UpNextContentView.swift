import SwiftUI
import MusicSearchKit
import SonosKit
import OrderedCollections

struct UpNextContentView: View {
    @Environment(PlayHistoryService.self) var playHistoryService
    @Binding var editMode: EditMode

    var group: GroupRoom
    var currentTrackID: String
    var router: Router
    @Binding var selection: Set<String>
    @Binding var upNext: [PlayableContent]

    @State private var isLoading: Bool = false
    @State private var isPaginating: Bool = true
    @State private var currentStartingIndex: Int = 0
    @State private var pageSize: Int = 50

    private var startPosition: Int { group.coordinatorRoom.track.position }
    private var paginationThreshold: Int { upNext.count - 30 }

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(Array(upNext.enumerated()), id: \.element.trackID) { index, track in
                    HStack(spacing: 0) {
                        Text(formatPosition(startPosition + index + 1))
                            .font(.caption.monospacedDigit().smallCaps())
                            .foregroundStyle(.secondary)
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
        isPaginating = false // Reset pagination state
        currentStartingIndex = group.coordinatorRoom.track.position // Start from current track position (0-based for API)
        upNext = await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip, with: currentStartingIndex, total: pageSize)
        group.coordinatorRoom.queueTotal = (try? await SonosService.shared.getQueueTotal(group: group)) ?? 0
        isLoading = false
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
        guard let sourceIndex = source.first else { return }
        
        // Get the actual queue positions from track metadata
        let sourceTrack = upNext[sourceIndex]
        let destinationTrack = destination < upNext.count ? upNext[destination] : upNext.last
        
        guard let actualSourcePosition = sourceTrack.metadata?.position,
              let actualDestinationPosition = destinationTrack?.metadata?.position else { return }
        
        // Move in local array for immediate UI feedback
        upNext.move(fromOffsets: source, toOffset: destination)
        
        Task {
            // Use actual queue positions for Sonos API
            try await SonosService.shared.reorderQueue(group, from: actualSourcePosition, to: actualDestinationPosition)
            
            // Refresh the up next list to get updated positions
            await loadUpNext()
        }
    }
}
