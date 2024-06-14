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
    @Environment(AlertService.self) private var alertService: AlertService
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService

    @State var playableContent: PlayableContent?

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
                        HapticManager.shared.fireHaptic(.buttonPress)
                        dismiss()
                        Task {
                            if let playableContent {
                                playHistoryService.history.remove(playableContent)
                                playHistoryService.history.insert(playableContent, at: 0)
                                alertService.showAlertContent(with: playableContent)
                                await sonosService.queue(playable: playableContent, group: group, position: position)
                                await sonosService.play(ip: group.ip)
                                return
                            }
                            if let mediaContent {
                                // TODO: Need to get content, get rid of just using mediacontent
                                //                                await sonosService.queue(content: mediaContent, group: group)
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
        .task {
            try? await sonosService.updateGroups()
            try? await sonosService.load(useCache: true)
        }
        .listStyle(.insetGrouped)
        .addDismiss {
            dismiss()
        }
    }
}


