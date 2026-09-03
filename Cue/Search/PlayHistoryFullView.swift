import Collections
import CloudStorage
import Defaults
import Foundation
import NukeUI
import SonosKit
import SwiftUI

struct PlayHistoryFullView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService

    @State private var clearHistoryConfirmation: Bool = false
    @State private var filters: [FilterSelection] = FilterSelection.defaultFilters

    var body: some View {
        List {
            // No services = the default chips; history spans services, so no
            // service-specific chips (Radio/Library) apply here.
            FilterView(filters: $filters)
                .listRowSeparator(.hidden)
            
            let filteredHistory = playHistoryService.history.filter { item in
                if filters.filter(\.isFiltered).isEmpty {
                    return true
                } else {
                    return filters.filter(\.isFiltered).flatMap(\.filter.toContentType).contains(item.content.type)
                }
            }

            ForEach(filteredHistory, id: \.trackID) { item in
                PlayableContentView(item: item)
            }
        }
        .miniPlayerOnScrollHandler()
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                if !playHistoryService.history.isEmpty {
                    Button(role: .destructive) {
                        clearHistoryConfirmation.toggle()
                    } label: {
                        Label("Remove All", systemImage: "trash.fill")
                            .labelStyle(.iconOnly)
                    }
                    .confirmationDialog("Clear Play History", isPresented: $clearHistoryConfirmation) {
                        Button {
                            playHistoryService.history.removeAll()
                        } label: {
                            Text("Remove Play History")
                                .bold()
                        }
                    }
                }
            }
        }
        .contentMargins(.bottom, 120, for: .scrollContent)
        .navigationTitle("Play History")
    }
}
