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
        NavigationLink(value: RouterDestination.fullPlayHistoryList) {
            Text("Play History")
        }
        .listRowSeparator(.hidden)
        .foregroundStyle(.secondary)
        .fontDesign(.rounded)
        .bold()
        
        ForEach(playHistoryService.history.prefix(5)) { item in
            if filters.filter(\.isFiltered).isEmpty {
                PlayableContentView(item: item)
            } else {
                if filters.filter(\.isFiltered).flatMap(\.filter.toContentType).contains(item.content.type) {
                    PlayableContentView(item: item)
                }
            }
        }
        .fontDesign(.rounded)
    }
}
