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

    var body: some View {
        Section {
            ForEach(Array(playHistory), id: \.self) { item in
                PlayableContentView(item: item, group: group)
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
                        playHistory.removeAll()
                    } label: {
                        Text("Clear All")
                            .bold()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
        }
    }
}
