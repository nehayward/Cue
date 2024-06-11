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
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService

    @Binding var filters: [FilterSelection]
    @State private var clearHistoryConfirmation: Bool = false

    var body: some View {
        Section {
            if filters.filter(\.isFiltered).isEmpty {
                ForEach(playHistoryService.history.prefix(10)) { item in
                    PlayableContentView(item: item, group: group)
                }
            } else {
                ForEach(playHistoryService.history.prefix(10)) { item in
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
                if !playHistoryService.history.isEmpty {
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
                    playHistoryService.history.removeAll()
                } label: {
                    Text("Remove Play History")
                    .bold()
                }
            }
        }
    }
}
