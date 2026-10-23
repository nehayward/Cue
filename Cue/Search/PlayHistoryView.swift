import Collections
import CloudStorage
import Defaults
import Foundation
import NukeUI
import SonosKit
import SwiftUI

struct PlayHistoryView: View {
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService

    @Binding var filters: [FilterSelection]
    @State private var clearHistoryConfirmation: Bool = false

    private var activeTypes: Set<ContentType>? {
        let active = filters.filter(\.isFiltered)
        guard !active.isEmpty else { return nil }
        return Set(active.flatMap(\.filter.toContentType))
    }

    /// The five rows shown, taken without copying or filtering the rest of
    /// the history.
    private var recentHistory: [PlayableContent] {
        guard let activeTypes else { return Array(playHistoryService.history.prefix(5)) }
        return Array(playHistoryService.history.lazy.filter { activeTypes.contains($0.content.type) }.prefix(5))
    }

    var body: some View {
        let history = recentHistory

        Section {
            NavigationLink(value: RouterDestination.fullPlayHistoryList) {
                Text("Play History")
                    .fontDesign(.rounded)
                    .fontWeight(.semibold)
            }
            .listRowSeparator(.hidden)
            // Stable: a fresh UUID re-tagged the row on every pass.
            .tag("playHistoryHeader")

            ForEach(history) { item in
                PlayableContentView(item: item)
            }
        }
        // Here rather than on the whole search screen, which then read (and
        // compared) the entire synced history on every update.
        .animation(.snappy, value: history)
        .listRowSpacing(0)
        .listSectionSpacing(0)
        .listRowInsets(.default)

        
    }
}
