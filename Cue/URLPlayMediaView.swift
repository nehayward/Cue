import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import NukeUI
import VibesDS

struct URLPlayMediaView: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(PlayHistoryService.self) private var playHistoryService
    @Environment(\.dismiss) private var dismiss

    let url: URL
    var position: QueuePosition = .now
    @State private var content: PlayableContent?

    var body: some View {
        SelectGroupView(content: content, defaultPosition: position, onQueueSelection: { group, selectedPosition in
            guard let content else { return }
            try await sonosService.queue(playable: content, group: group, position: selectedPosition)
            playHistoryService.record(content)
            await sonosService.play(ip: group.ip)
        })
        .task {
            if content == nil {
                content = await sonosService.getContent(from: url)
            }
        }
        .environment(SelectedGroupService())
    }
}
