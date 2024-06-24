import CloudStorage
import MusicSearchKit
import Defaults
import NukeUI
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults

struct PlayableContentView: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router
    @Environment(ContentToAdd.self) private var adding: ContentToAdd?
    @Environment(AlertService.self) private var alertService: AlertService
    @Environment(PlaylistContainer.self) private var playlistsContainer: PlaylistContainer
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    var item: PlayableContent
    var hideArtwork: Bool = false

    var body: some View {
        Group {
            if let add = adding?.add, add {
                content
            } else {
                switch item.content.type {
                case .playlist, .album, .userPlaylist:
                    NavigationLink(value: RouterDestination.mediaDetail(content: item, group: selectedGroupService.group)) {
                        content
                    }
                case .artist:
                    NavigationLink(value: RouterDestination.artistDetail(content: item, group: selectedGroupService.group)) {
                        content
                    }
                case .track, .favorite, .radio:
                    content
                case .libraryTrack:
                    content
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden, edges: .all)
    }

    private var content: some View {
        Button {
            play(replaceQueue: item.content.type == .playlist)
        } label: {
            HStack {
                if !hideArtwork {
                    ContentArtworkView(content: item)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                }
                VStack(alignment: .leading) {
                    Text(item.title)
                        .lineLimit(1)
                    HStack(spacing: 0) {
                        Text("\(item.content.type.title)\(item.subtitle.isEmpty ? "" : " • \(item.subtitle)")")

                        // MARK: Add back when you normalize duration to seconds
//                        if let duration = item.metadata?.duration, duration.components.seconds != 0 {
//                            Text(" • ")
//                            Text(duration, format: .time(pattern: .minuteSecond))
//                        }
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer()
                switch item.content.type {
                case .track, .favorite:
                    if adding == nil {
                        Menu {
                            menu
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(maxWidth: 40, maxHeight: .infinity, alignment: .trailing)
                                .background(.clear)
                        }
                    }
                default:
                    EmptyView()
                }
            }
            .fontDesign(.rounded)
        }
        .swipeActions {
            if playHistoryService.history.contains(item) {
                Button(role: .destructive) {
                    playHistoryService.history.remove(item)
                } label: {
                    Label("Remove from History", systemImage: "trash")
                }
            }
        }
        .contentShape(.contextMenuPreview, Capsule())
        .contextMenu {
            if adding == nil {
                menu
            }
        }
        .draggable(item)
    }


    private var menu: some View {
        VStack {
            if playHistoryService.history.contains(item) {
                Button(role: .destructive) {
                    playHistoryService.history.remove(item)
                } label: {
                    Label("Remove from History", systemImage: "trash")
                }
            }
            OpenInServiceView(item: item)
            switch item.content.type {
            case .artist:
                NavigationLink(value: RouterDestination.artistDetail(content: item, group: selectedGroupService.group)) {
                    Label("View Artist", systemImage: "music.mic")
                }

                if [.apple, .spotify].contains(item.content.service) {
                    Button {
                        guard let group = selectedGroupService.group else { return }
                        Task {
                            await HapticManager.shared.fireHaptic(.buttonPress)
                            await sonosService.startRadio(content: item, group: group)
                        }
                    } label: {
                        Label("Start Radio", systemImage: "radio.fill")
                    }
                }
            case .playlist, .userPlaylist:
                ControlGroup {
                    Button {
                        play(replaceQueue: true)
                    } label: {
                        Label("Replace Queue", systemImage: "play.fill")
                    }

                    Button {
                        play(position: .next)
                    } label: {
                        Label("Play Next", systemImage: "text.line.last.and.arrowtriangle.forward")
                    }

                    Button {
                        play(position: .end)
                    } label: {
                        Label("Play Last", systemImage: "text.append")
                    }
                }

                if item.content.service == .library, item.content.id.last?.isNumber ?? false {
                    Button {
                        router.sheet(to: .renamePlaylist(content: item))
                    } label: {
                        Label("Rename", systemImage: "textformat")
                    }
                }
// TODO: Add scene playlist
//                NavigationLink(value: RouterDestination.createScene(content: item)) {
//                    Label("Create Scene", systemImage: "bolt.fill")
//                }

            case .album, .track, .libraryTrack:
                if [.album, .track].contains(item.content.type) {
                    NavigationLink(value: RouterDestination.mediaDetail(content: item, group: selectedGroupService.group)) {
                        Label("Album", systemImage: "smallcircle.circle.fill")
                    }


                    NavigationLink(value: RouterDestination.artistDetail(content: item, group: selectedGroupService.group)) {
                        Label("Artist", systemImage: "music.mic")
                    }

                    // TODO: Add scene playlist
//                    NavigationLink(value: RouterDestination.createScene(content: item)) {
//                        Label("Create Scene", systemImage: "bolt.fill")
//                    }
                }

                ControlGroup {
                    if item.content.type == .album {
                        Button {
                            play(replaceQueue: true)
                        } label: {
                            Label("Replace Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
                        }
                    }

                    Button {
                        play(position: .next)
                    } label: {
                        Label("Play Next", systemImage: "text.badge.plus")
                    }

                    Button {
                        play(position: .end)
                    } label: {
                        Label("Play Last", systemImage: "text.append")
                    }
                }

                AddToPlaylistMenu(itemToAdd: item)
            case .radio, .favorite:
                Button {
                    play()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
            }
        }
    }

    private func play(position: QueuePosition = .now, replaceQueue: Bool = false) {
        if let add = adding?.add, add {
            adding?.content = item
            router.dismiss = true
            return
        }
        Task { @MainActor in
            hideKeyboard()
            let queueSong: ((GroupRoom) async -> Void) = { group in
                playHistoryService.history.remove(item)
                playHistoryService.history.insert(item, at: 0)
                HapticManager.shared.fireHaptic(.buttonPress)
                await sonosService.queue(playable: item, group: group, position: position, replaceQueue: replaceQueue)
                await sonosService.play(ip: group.coordinatorRoom.ip)
            }
            guard let group = selectedGroupService.group else {
                router.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onSelection: queueSong))
                return
            }
            await queueSong(group)
        }
    }
}

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
