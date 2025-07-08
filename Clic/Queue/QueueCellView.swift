import SwiftUI
import MusicSearchKit
import SonosKit
import OrderedCollections
import Nuke

struct QueueCellView: View {
    var track: PlayableContent
    @Bindable var group: GroupRoom
    var currentTrackID: String
    var router: Router
    var isEditing: Bool
    var onLocalDelete: ((PlayableContent) -> Void)? = nil
    
    var body: some View {
//        let _ = Self._printChanges()
//        let _ = print("\(track.metadata?.position) update")
        Button {
            Task {
                HapticManager.shared.fireHaptic(.buttonPress)
                guard let position = track.metadata?.position else { return }
                await SonosService.shared.seek(trackNumber: position, on: group)
                await SonosService.shared.play(ip: group.coordinatorRoom.ip)
            }
        } label: {
            HStack {
                LightArtworkView(content: track, contentType: track.content.type, showMusicSource: true)
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
                    QueueCellMenuView(track: track, group: group, router: router, onLocalDelete: onLocalDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(maxWidth: 50, maxHeight: .infinity)
                        .background(.clear)
                        .tint(.primary)
                        .bold()
                }
                .transition(.identity)
                .opacity(isEditing ? 0 : 1)
                .frame(width: isEditing ? 0 : nil)
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                Task {
                    guard let position = track.metadata?.position else { return }
                    
                    // Remove from local array first for immediate UI feedback
                    onLocalDelete?(track)
                    
                    try? await SonosService.shared.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
                    group.coordinatorRoom.queueTotal = (try? await SonosService.shared.getQueueTotal(group: group)) ?? 0
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 0))
        .draggable(track)
    }
    
    private var isTrackPlaying: Bool {
        return currentTrackID == track.trackID && group.playbackService == .queue
    }
}

fileprivate struct QueueCellMenuView: View {
    let track: PlayableContent
    @Bindable var group: GroupRoom
    let router: Router
    var onLocalDelete: ((PlayableContent) -> Void)? = nil
    
    var body: some View {
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
                Task {
                    guard let position = track.metadata?.position else { return }
                    
                    // Remove from local array first for immediate UI feedback
                    onLocalDelete?(track)
                    
                    try? await SonosService.shared.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
                    group.coordinatorRoom.queueTotal = (try? await SonosService.shared.getQueueTotal(group: group)) ?? 0
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

