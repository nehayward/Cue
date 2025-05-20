import Collections
import CloudStorage
import Defaults
import Foundation
import NukeUI
import SonosKitMini
import SwiftUI

struct PlayHistoryView: View {
    @Environment(SonosMiniService.self) var sonosService: SonosMiniService
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService

    let id: String

    var body: some View {
        NavigationStack {
            List {
                ForEach(playHistoryService.history.prefix(10)) { item in
                    Button {
//                        play(item: item)
                    } label: {
                        HStack {
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
    
    private func play(item: PlayableContent, queuePlacement: SonosQueuePlacement = .now) {
        Task { @MainActor in
            let queueSong: ((SonosDevice) async throws -> Void) = { group in
                do {
//                    try await sonosService.queue(playable: item, group: group, position: position)
//                    await sonosService.play(ip: group.coordinatorRoom.ip)
//                    playHistoryService.history.remove(item)
//                    playHistoryService.history.insert(item, at: 0)
                }
            }
//            try await queueSong(group)
        }
    }
}
