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
    var onLocalMoveNext: ((PlayableContent) -> Void)? = nil
    var onLocalDelete: ((PlayableContent) -> Void)? = nil

    @State private var audioService = AudioPlaybackService.shared

    private var isPreviewing: Bool {
        guard let url = track.previewURL else { return false }
        return audioService.isPreviewing(url)
    }

    private var previewProgress: Double {
        guard audioService.duration > 0 else { return 0 }
        return min(1, audioService.playbackProgress / audioService.duration)
    }

    var body: some View {
//        let _ = Self._printChanges()
//        let _ = print("\(track.title) update")
        Button {
            if isPreviewing {
                AudioPlaybackService.shared.stopPreview()
            } else {
                Task {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    guard let position = track.metadata?.position else { return }
                    await SonosService.shared.seek(trackNumber: position, on: group)
                    await SonosService.shared.play(ip: group.coordinatorRoom.ip)
                }
            }
        } label: {
            HStack(alignment: .center) {
                LightArtworkView(content: track, contentType: track.content.type, showMusicSource: true)
                    .frame(width: 50, height: 50)
                    #if DEBUG && SCREENSHOT
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .foregroundStyle(.ultraThinMaterial)
                    }
                    #endif
                VStack(alignment: .leading) {
                    Text(track.title)
                        .lineLimit(1)
                        .foregroundStyle(isTrackPlaying ? AnyShapeStyle(.accent) : AnyShapeStyle(.primary))
                    Text(track.subtitle)
                        .opacity(0.7)
                        .font(.footnote)
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    QueueCellMenuView(track: track, group: group, router: router, onLocalMoveNext: onLocalMoveNext, onLocalDelete: onLocalDelete)
                        .tint(.white)
                        .foregroundStyle(.white)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(maxWidth: 50, maxHeight: .infinity)
                        .background(.clear)
                        .tint(.primary)
                        .bold()
                        .opacity(isPreviewing ? 0 : 1)
                }
                .contentTransition(.identity)
                .opacity(isEditing ? 0 : 1)
                .frame(width: isEditing ? 0 : nil)
                .disabled(isPreviewing)
                .overlay {
                    if isPreviewing, !isEditing {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .tint(.primary)
        .background(alignment: .leading) {
            Color.accentColor.opacity(0.12)
                .scaleEffect(x: isPreviewing ? previewProgress : 0, anchor: .leading)
                .animation(.linear(duration: 0.3), value: previewProgress)
        }
        .onDisappear {
            if isPreviewing { AudioPlaybackService.shared.stopPreview() }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    guard let position = track.metadata?.position else { return }
                    onLocalDelete?(track)
                    try? await SonosService.shared.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
                    group.coordinatorRoom.queueTotal = (try? await SonosService.shared.getQueueTotal(group: group)) ?? 0
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        .swipeActions(edge: .leading) {
            if let previewURL = track.previewURL,
               !previewURL.absoluteString.isEmpty,
               [.track, .libraryTrack].contains(track.content.type) {
                Button {
                    AudioPlaybackService.shared.preview(url: previewURL)
                } label: {
                    Label("Preview", systemImage: "play.circle.fill")
                }
                .tint(.accentColor)
            }
        }
        .contextMenu {
            QueueCellMenuView(track: track, group: group, router: router, onLocalMoveNext: onLocalMoveNext, onLocalDelete: onLocalDelete)
        } preview: {
            SongPreviewCard(item: track)
        }
        .draggable(track) {
            Text(track.title)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.background, in: .capsule)
                .contentShape(.dragPreview, .capsule)
        }
    }
    
    private var isTrackPlaying: Bool {
        currentTrackID == track.trackID && group.playbackService == .queue
    }
}

fileprivate struct QueueCellMenuView: View {
    let track: PlayableContent
    @Bindable var group: GroupRoom
    let router: Router
    var onLocalMoveNext: ((PlayableContent) -> Void)? = nil
    var onLocalDelete: ((PlayableContent) -> Void)? = nil
    
    var body: some View {
        VStack {
            if track.content.service != .unknown {
                if let previewURL = track.previewURL, !previewURL.absoluteString.isEmpty,
                   [.track, .libraryTrack].contains(track.content.type) {
                    SongPreviewButton(previewURL: previewURL)
                }

                AddToLastPlaylistButton(itemToAdd: track)
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

            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                onLocalMoveNext?(track)
                Task {
                    guard let position = track.metadata?.position else { return }
                    let nextPosition = group.coordinatorRoom.track.position + 1
                    guard position != nextPosition else { return }
                    try? await SonosService.shared.reorderQueue(group, from: position, to: nextPosition)
                }
            } label: {
                Text("Move to Top")
                Text("After \(group.coordinatorRoom.track.name)")
                Image(systemName: "text.insert")
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
