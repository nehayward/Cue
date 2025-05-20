import SwiftUI
import MusicSearchKit
import SonosKit
import OrderedCollections
import Nuke

struct QueueCellView: View {
    var track: PlayableContent
    var group: GroupRoom
    var currentTrackID: String
    var router: Router
    @State var thumbnail: URL?
    
    var body: some View {
        @Bindable var group = group
//        let _ = Self._printChanges()

//        let _ = print("\(track.metadata?.position) update")
        Button {
            Task {
                HapticManager.shared.fireHaptic(.buttonPress)
                guard let position = track.metadata?.position else { return }
                await SonosService.shared.seek(trackNumber: position, on: group)
                await SonosService.shared.play(ip: group.coordinatorRoom.ip)
                group.coordinatorRoom.queue = OrderedSet(await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip))
                group.coordinatorRoom.queueTotal = (try? await SonosService.shared.getQueueTotal(group: group)) ?? 0
            }
        } label: {
            HStack {
                LightArtworkView(thumbnail: $thumbnail, content: track, id: track.id, contentType: track.content.type, showMusicSource: true)
                    .frame(width: 50, height: 50)
                VStack(alignment: .leading) {
                    Text(track.title)
                        .lineLimit(1)
                        .foregroundStyle(isTrackPlaying ? .accent : .primary)
                    Text(track.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    menu
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(maxWidth: 50, maxHeight: .infinity)
                        .background(.clear)
                        .tint(.primary)
                        .bold()
                }
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                guard let position = track.metadata?.position else { return }
                group.coordinatorRoom.queue.remove(at: position - 1)
                Task {
                    try? await SonosService.shared.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
                    group.coordinatorRoom.queue = OrderedSet(await SonosService.shared.getQueue(ip: group.ip))
                    group.coordinatorRoom.queueTotal = (try? await SonosService.shared.getQueueTotal(group: group)) ?? 0
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 0))
        .draggable(track)
        .task {
            if let cache = try? DataCache(name: "com.clic.imageCache"), cache.containsData(for: track.id) {
                thumbnail = cache.url(for: track.id)
                return
            }
            
            guard let thumbnail = await SonosService.shared.getArtwork(from: track, size: 50) else {
                return
            }
            
            self.thumbnail = thumbnail
        }
       
    }
    
    private var isTrackPlaying: Bool {
        return currentTrackID == track.trackID && group.playbackService == .queue
    }
    
    @ViewBuilder
    private var menu: some View {
        VStack {
            if track.content.service != .unknown {
                AddToPlaylistMenu(itemToAdd: track)

                Button {
                    router.navigate(to: .mediaDetail(content: track, group: group))
                } label: {
                    Label("View Album", systemImage: "smallcircle.circle.fill")
                }

                Button {
                    router.navigate(to: .artistDetail(content: track, group: group))
                } label: {
                    Label("View Artist", systemImage: "music.mic")
                }
            }

            Button(role: .destructive) {
                guard let position = track.metadata?.position else { return }
                group.coordinatorRoom.queue.remove(at: position - 1)
                Task {
                    try? await SonosService.shared.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
                    group.coordinatorRoom.queue = OrderedSet(await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip))
                    group.coordinatorRoom.queueTotal = (try? await SonosService.shared.getQueueTotal(group: group)) ?? 0
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

