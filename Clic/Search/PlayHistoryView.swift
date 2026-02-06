import Collections
import CloudStorage
import Defaults
import Foundation
import NukeUI
import SonosKit
import SwiftUI

struct PlayHistoryView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService

    @Binding var filters: [FilterSelection]
    @State private var clearHistoryConfirmation: Bool = false

    var body: some View {
        Button {
            router.navigate(to: .fullPlayHistoryList)
        } label: {
            Text("Play History")
        }
        .listRowSeparator(.hidden)
        .foregroundStyle(.secondary)
        .fontDesign(.rounded)
        .bold()
        
        let filteredHistory = playHistoryService.history.filter { item in
            if filters.filter(\.isFiltered).isEmpty {
                return true
            } else {
                return filters.filter(\.isFiltered).flatMap(\.filter.toContentType).contains(item.content.type)
            }
        }

        ForEach(filteredHistory.prefix(5)) { item in
            PlayableContentView(item: item)
        }
        .fontDesign(.rounded)
    }
}
