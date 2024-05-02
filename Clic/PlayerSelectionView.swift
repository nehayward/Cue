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

    @CloudStorage(CloudKeys.playHistory) var playHistory: OrderedSet<PlayableContent> = []

    @State var playableContent: PlayableContent?
    var mediaContent: MediaContent?
    @State var artworkURL: URL?

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
                        router?.dismiss = true
                        dismiss()
                        Task {
                            if let playableContent {
                                playHistory.remove(playableContent)
                                playHistory.insert(playableContent, at: 0)
                                await sonosService.queue(content: playableContent.content, group: group)
                                await sonosService.play(ip: group.ip)
                                return
                            }
                            if let mediaContent {
                                await sonosService.queue(content: mediaContent, group: group)
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
                .swipeActions {
                    Button {
                        router?.dismiss = true
                        dismiss()
                        Task {
                            if let playableContent {
                                playHistory.remove(playableContent)
                                playHistory.insert(playableContent, at: 0)
                                await sonosService.queue(content: playableContent.content, group: group, position: .next)
                            }
                            if let mediaContent {
                                await sonosService.queue(content: mediaContent, group: group, position: .next)
                            }
                            await sonosService.play(ip: group.ip)
                        }
                    } label: {
                        Label("Play Next", systemImage: "text.line.last.and.arrowtriangle.forward")
                            .font(.caption)
                    }
                }
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


