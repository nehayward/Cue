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
        Text("Play History")
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
            .fontDesign(.rounded)
            .bold()
        ForEach(playHistoryService.history.prefix(5)) { item in
            if filters.filter(\.isFiltered).isEmpty {
                PlayableContentView(item: item)
            } else {
                if filters.filter(\.isFiltered).map(\.filter.toContentType).contains(item.content.type) {
                    PlayableContentView(item: item)
                }
            }
        }
        .fontDesign(.rounded)

        if !playHistoryService.history.isEmpty {
            NavigationLink(value: RouterDestination.fullPlayHistoryList) {
                Text("Show all")
            }
        }
    }
}
