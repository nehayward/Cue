import MusicSearchKit
import SonosKit
import SwiftUI

/// Shared empty state for the queue and "Up Next" screens.
///
/// Instead of a bare "Nothing up next" message, this surfaces recently played
/// content as tappable rows so there's always something to play.
struct EmptyQueueView: View {
    @Environment(PlayHistoryService.self) private var playHistoryService

    var title: String
    var message: String

    private var recentlyPlayed: [PlayableContent] {
        Array(playHistoryService.history.prefix(12))
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 28) {
                    header

                    if !recentlyPlayed.isEmpty {
                        recentlySection
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

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var recentlySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Play History")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                ForEach(recentlyPlayed) { item in
                    PlayableContentRowView(item: item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
