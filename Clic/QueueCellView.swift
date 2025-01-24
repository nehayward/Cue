import SwiftUI
import MusicSearchKit
import SonosKit
import OrderedCollections

struct QueueCellView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(SonosService.self) var sonosService
    
    let track: PlayableContent
    @Binding var group: GroupRoom
    var router: Router
    @State private var isHovered = false
    
    private var isCatalyst: Bool {
#if targetEnvironment(macCatalyst)
        return true
#endif
        return UIDevice.current.userInterfaceIdiom == .pad
    }
    
    var body: some View {
        Button {
            dismiss()
            Task {
                HapticManager.shared.fireHaptic(.buttonPress)
                guard let position = track.metadata?.position else { return }
                await sonosService.seek(trackNumber: position, on: group)
                await sonosService.play(ip: group.coordinatorRoom.ip)
                group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.coordinatorRoom.ip))
            }
        } label: {
            HStack {
                ContentArtworkView(content: track)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                VStack(alignment: .leading) {
                    Text(track.title)
                        .lineLimit(1)
                    Text(track.subtitle)
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
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isTrackPlaying ? Color(uiColor: UIColor.systemFill) :
                        isHovered && isCatalyst ? Color(uiColor: UIColor.tertiarySystemFill) : Color.clear
                )
                .padding(.horizontal, 4)
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 0))
        .bold(isTrackPlaying)
        .draggable(track)
        .onHover { hovering in
            if isCatalyst {
                isHovered = hovering
            }
        }
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
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

