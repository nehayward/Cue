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
    @Environment(GroupRoom.self) var group: GroupRoom?

    @CloudStorage(CloudKeys.playHistory) var playHistory: OrderedSet<PlayableContent> = []
    @Binding var filters: [FilterSelection]
    @State private var clearHistoryConfirmation: Bool = false

    var body: some View {
        Section {
            if filters.filter(\.isFiltered).isEmpty {
                ForEach(playHistory) { item in
                    PlayableContentView(item: item, group: group)
                }
            } else {
                ForEach(playHistory) { item in
                    if filters.filter(\.isFiltered).map(\.filter.toContentType).contains(item.content.type) {
                        PlayableContentView(item: item, group: group)
                    }
                }
            }

        } header: {
            HStack {
                Label {
                    Text("Play History")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                Spacer()
                if !playHistory.isEmpty {
                    Button {
                        clearHistoryConfirmation.toggle()
                    } label: {
                        Text("Clear All")
                            .bold()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
            .confirmationDialog("Clear Play History", isPresented: $clearHistoryConfirmation) {
                Button {
                    playHistory.removeAll()
                } label: {
                    Text("Remove Play History")
                    .bold()
                }
            }
        }
    }
}
