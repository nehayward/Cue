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

    private var filteredHistory: [PlayableContent] {
        guard let activeTypes else { return Array(playHistoryService.history) }
        return playHistoryService.history.filter { activeTypes.contains($0.content.type) }
    }

    var body: some View {
        let history = filteredHistory

        Section {
            NavigationLink(value: RouterDestination.fullPlayHistoryList) {
                Text("Play History")
                    .fontDesign(.rounded)
                    .fontWeight(.semibold)
            }
            .listRowSeparator(.hidden)
            .tag(UUID().uuidString)

            ForEach(history.prefix(5)) { item in
                PlayableContentView(item: item)
            }
        }
        .listRowSpacing(0)
        .listSectionSpacing(0)
        .listRowInsets(.default)

        
    }
}
