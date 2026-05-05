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
        SelectGroupView(content: content) { group in
            guard let content else { return }
            try await sonosService.queue(playable: content, group: group, position: position)
            playHistoryService.history.remove(content)
            playHistoryService.history.insert(content, at: 0)
            await sonosService.play(ip: group.ip)
        }
        .task {
            if content == nil {
                content = await sonosService.getContent(from: url)
            }
        }
        .environment(SelectedGroupService())
    }
}
