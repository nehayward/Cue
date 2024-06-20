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
            NavigationLink {
                List {
                    ForEach(playHistoryService.history) { item in
                        if filters.filter(\.isFiltered).isEmpty {
                            PlayableContentView(item: item)
                        } else {
                            if filters.filter(\.isFiltered).map(\.filter.toContentType).contains(item.content.type) {
                                PlayableContentView(item: item)
                            }
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .destructiveAction) {
                        if !playHistoryService.history.isEmpty {
                            Button(role: .destructive) {
                                clearHistoryConfirmation.toggle()
                            } label: {
                                Text("Remove All")
                            }
                        }
                    }
                }
                .contentMargins(.bottom, 80, for: .scrollContent)
                .navigationTitle("Play History")
                .confirmationDialog("Clear Play History", isPresented: $clearHistoryConfirmation) {
                    Button {
                        playHistoryService.history.removeAll()
                    } label: {
                        Text("Remove Play History")
                            .bold()
                    }
                }
            } label: {
                Text("Show All")
            }
        }
    }
}
