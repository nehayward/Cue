import Collections
import CloudStorage
import Defaults
import Foundation
import NukeUI
import SonosKit
import SwiftUI

struct PlayHistoryView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService

    @Binding var group: GroupRoom

    var body: some View {
        NavigationStack {
            List {
                ForEach(playHistoryService.history.prefix(10)) { item in
                    Button {
                        play(item: item)
                    } label: {
                        HStack {
                            ThumbnailView(content: item, preferredSize: 40)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                            VStack(alignment: .leading) {
                                Text(item.title)
                                Text(item.subtitle)
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                        }
                    }
                }
                .fontDesign(.rounded)
            }
            .navigationTitle("Play History")
        }
    }
    
    private func play(item: PlayableContent, position: QueuePosition = .now, replaceQueue: Bool = false) {
        Task { @MainActor in
            let queueSong: ((GroupRoom) async throws -> Void) = { group in
                do {
                    try await sonosService.queue(playable: item, group: group, position: position, replaceQueue: replaceQueue)
                    await sonosService.play(ip: group.coordinatorRoom.ip)
                    playHistoryService.history.remove(item)
                    playHistoryService.history.insert(item, at: 0)
                }
            }
            try await queueSong(group)
        }
    }
}
