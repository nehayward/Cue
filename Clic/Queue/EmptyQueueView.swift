import MusicSearchKit
import SonosKit
import SwiftUI

/// Shared empty state for the queue and "Up Next" screens.
///
/// Instead of a bare "Nothing up next" message, this surfaces recently played
/// content as tappable rows so there's always something to play — plus a search
/// shortcut and a one-tap shuffle of your history.
struct EmptyQueueView: View {
    @Environment(PlayHistoryService.self) private var playHistoryService
    @Environment(Router.self) private var router: Router?
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService?

    var title: String
    var message: String

    /// Recently played history, de-duplicated by title + artist so the same song
    /// from different services (or repeat plays) doesn't stack up, capped at 12.
    private var recentlyPlayed: [PlayableContent] {
        var seen = Set<String>()
        var result: [PlayableContent] = []
        for item in playHistoryService.history {
            let key = "\(item.title.lowercased())|\(item.subtitle.lowercased())"
            guard seen.insert(key).inserted else { continue }
            result.append(item)
            if result.count == 12 { break }
        }
        return result
    }

    private var hasHistory: Bool { !recentlyPlayed.isEmpty }

    /// History entries that can actually be added to the queue. Radio stations
    /// (and artists/folders) set the transport or navigate instead of queueing,
    /// so they can't take part in a shuffle-into-queue.
    private var shuffleItems: [PlayableContent] {
        recentlyPlayed.filter { content in
            let type = content.content.type
            return type.isTrack || type.isPlaylist || type == .album || type == .libraryAlbum
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    header
                    searchButton

                    if hasHistory {
                        recentlySection
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .fontDesign(.rounded)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title3.bold())

            // The passed-in copy points "below" at the history list; when there's
            // no history to show, fall back to a message that stands on its own.
            Text(hasHistory ? message : "Search for a song, album, or playlist to start playing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var searchButton: some View {
        Button {
            router?.sheet(to: .search(group: selectedGroupService?.group))
        } label: {
            Label("Search Music", systemImage: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.accent)
    }

    private var recentlySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Play History")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                if shuffleItems.count > 1 {
                    Button(action: shufflePlay) {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }

            VStack(spacing: 4) {
                ForEach(recentlyPlayed) { item in
                    PlayableContentRowView(item: item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Shuffle the shown history into the queue and start playing. The order is
    /// shuffled up front (rather than toggling Sonos shuffle) so the result is
    /// deterministic and doesn't depend on play-mode timing: the first item
    /// replaces the queue and plays, the rest append in shuffled order.
    private func shufflePlay() {
        let items = shuffleItems.shuffled()
        guard !items.isEmpty else { return }

        Task { @MainActor in
            let enqueue: (GroupRoom) async throws -> Void = { group in
                let queueItems = items.enumerated().map { index, content in
                    QueueItem(
                        playableContent: content,
                        group: group,
                        position: index == 0 ? .replace : .end,
                        showBanner: false
                    )
                }
                QueueManager.shared.add(items: queueItems)
                router?.show(destination: .player(groupID: group.coordinatorID))
            }

            guard let group = selectedGroupService?.group else {
                if let selectedGroupService {
                    router?.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onSelection: enqueue))
                }
                return
            }
            try await enqueue(group)
        }
    }
}

#Preview("Up Next – Empty") {
    EmptyQueueView(
        title: "Nothing up next",
        message: "When something's playing, what's coming up shows here. Tap below to start something new."
    )
    .withEnvironments()
    .environment(SelectedGroupService(group: nil))
    .environment(Router())
}

#Preview("Queue – Empty") {
    EmptyQueueView(
        title: "Your queue is empty",
        message: "Add songs, albums, or playlists to build a queue. Pick up where you left off below."
    )
    .withEnvironments()
    .environment(SelectedGroupService(group: nil))
    .environment(Router())
}
