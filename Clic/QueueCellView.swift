import SwiftUI
import MusicSearchKit
import SonosKit
import OrderedCollections

struct QueueCellView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(SonosService.self) var sonosService
    
    let track: PlayableContent
    var group: GroupRoom
    var router: Router
    
    private var isCatalyst: Bool {
#if targetEnvironment(macCatalyst)
        return true
#endif
        return UIDevice.current.userInterfaceIdiom == .pad
    }
    
    var body: some View {
        @Bindable var group = group
//        let _ = print("\(track.metadata?.position) update")

        Button {
            dismiss()
            Task {
                HapticManager.shared.fireHaptic(.buttonPress)
                guard let position = track.metadata?.position else { return }
                await sonosService.seek(trackNumber: position, on: group)
                await sonosService.play(ip: group.coordinatorRoom.ip)
                group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.coordinatorRoom.ip))
                group.coordinatorRoom.queueTotal = (try? await sonosService.getQueueTotal(group: group)) ?? 0
            }
        } label: {
            HStack {
                ContentArtworkView(content: track)
                    .aspectRatio(contentMode: .fit)
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
                    try? await sonosService.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
                    group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.ip))
                    group.coordinatorRoom.queueTotal = (try? await sonosService.getQueueTotal(group: group)) ?? 0
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 0))
        .draggable(track)
       
    }
    
    private var isTrackPlaying: Bool {
        guard let position = track.metadata?.position else { return false }
        return group.coordinatorRoom.track.position == position && group.playbackService == .queue
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
                    try? await sonosService.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
                    group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.coordinatorRoom.ip))
                    group.coordinatorRoom.queueTotal = (try? await sonosService.getQueueTotal(group: group)) ?? 0
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

