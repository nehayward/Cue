import MusicSearchKit
import SonosKit
import SwiftUI

/// Shared empty state for the queue and "Up Next" screens.
///
/// Instead of a bare "Nothing up next" message, this surfaces recently played
/// content as tappable cover art so there's always something to play.
struct EmptyQueueView: View {
    @Environment(PlayHistoryService.self) private var playHistoryService

    var title: String
    var message: String
    var systemImage: String = "music.note.list"

    private var recentlyPlayed: [PlayableContent] {
        Array(playHistoryService.history.prefix(6))
    }

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                if !recentlyPlayed.isEmpty {
                    recentlySection
                }
            }
            .padding(.horizontal)
            .padding(.top, 32)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fontDesign(.rounded)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 72, height: 72)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.bold())

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var recentlySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recently Played", systemImage: "clock.arrow.circlepath")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(recentlyPlayed) { item in
                    PlayableCardView(item: item)
                }
            }
        }
    }
}

#Preview("Up Next – Empty") {
    EmptyQueueView(
        title: "Nothing up next",
        message: "When something's playing, what's coming up appears here. Tap to start something new.",
        systemImage: "music.note.list"
    )
    .withEnvironments()
    .environment(SelectedGroupService(group: nil))
    .environment(Router())
}

#Preview("Queue – Empty") {
    EmptyQueueView(
        title: "Your queue is empty",
        message: "Add songs, albums, or playlists to build a queue. Pick up where you left off below.",
        systemImage: "list.bullet"
    )
    .withEnvironments()
    .environment(SelectedGroupService(group: nil))
    .environment(Router())
}
