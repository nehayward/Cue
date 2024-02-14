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
        Section("Play History") {
            ForEach(Array(playHistory), id: \.self) { item in
                Button {
                    Task {
                        guard let group = group else {
                            router.navigate(to: .groupDestination(content: item))
                            return
                        }
                        router.dismiss = true
                        await sonosService.queue(content: item.content, group: group)
                        await sonosService.play(ip: group.coordinatorRoom.ip)
                    }
                } label: {
                    HStack {
                        ContentArtworkView(content: .constant(item))
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                        VStack(alignment: .leading) {
                            Text(item.title)
                            Text("\(item.content.type.title) • \(item.subtitle)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        playHistory.remove(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contentShape(.contextMenuPreview, Capsule())
                .contextMenu {
                    Button("Remove", role: .destructive) {
                        playHistory.remove(item)
                    }
                }
            }
            if !playHistory.isEmpty {
                Button {
                    playHistory.removeAll()
                } label: {
                    Text("Clear Play History")
                        .bold()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .listRowSeparator(.hidden)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
            }
        }
    }
}
