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

    @CloudStorage(CloudKeys.playHistory) var playHistory: OrderedSet<PlayableContent> = []

    @State var playableContent: PlayableContent?
    @State var artworkURL: URL?

    var position: QueuePosition = .now
    var mediaContent: MediaContent?

    var body: some View {
        @Bindable var sonosService = sonosService

        VStack {
            HStack(alignment: .top) {
                ContentArtworkView(content: $playableContent)
                    .transition(.scale)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                if let playableContent {
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
                                playHistory.remove(playableContent)
                                playHistory.insert(playableContent, at: 0)
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
            }
            .listRowSpacing(10)
        }
        .task {
            if let mediaContent {
                playableContent = await sonosService.getContent(from: mediaContent)
                artworkURL =  await sonosService.getArtwork(from: mediaContent)
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


