import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import NukeUI
import VibesDS

struct PlayerSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router: Router?
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService?

    @State var playableContent: PlayableContent?

    var urlScheme: URL?
    var position: QueuePosition = .now
    var mediaContent: MediaContent?

    var body: some View {
        @Bindable var sonosService = sonosService

        VStack {
            HStack(alignment: .top) {
                if let playableContent {
                    ContentArtworkView(content: playableContent)
                        .transition(.scale)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                    VStack(alignment: .leading) {
                        Text(playableContent.title)
                        Text(playableContent.subtitle)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fontDesign(.rounded)
                    .padding(.horizontal)
                } else {
                    ProgressView()
                }
            }
            .padding(.horizontal)

            List ($sonosService.sorted) { $group in
                VStack(alignment: .leading) {
                    Button {
                        selectedGroupService?.group = group
                        HapticManager.shared.fireHaptic(.buttonPress)
                        dismiss()
                        Task {
                            if let playableContent {
                                playHistoryService.history.remove(playableContent)
                                playHistoryService.history.insert(playableContent, at: 0)
                                await sonosService.queue(playable: playableContent, group: group, position: position)
                                await sonosService.play(ip: group.ip)
                                try? await Task.sleep(for: .milliseconds(100))
                                try? await sonosService.updateGroups(from: [group])
                                return
                            }
                            await sonosService.play(ip: group.ip)
                        }
                    } label: {
                        Text(group.nameWithCount)
                            .fontDesign(.rounded)
                            .bold()
                    }
                    VolumeControlView(group: $group, touchDelay: 0.05)
                }
                .foregroundStyle(.primary)
                .listRowBackground(Rectangle().foregroundColor(.clear).background(Material.bar))
            }
            .listRowSpacing(10)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if playableContent == nil, let url = urlScheme {
                playableContent = await sonosService.getContent(from: url)
            }
            try? await sonosService.updateGroups()
            try? await sonosService.load(useCache: true)
        }
        .listStyle(.insetGrouped)
        .addDismiss {
            dismiss()
        }
    }
}


