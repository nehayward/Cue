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
    @Environment(SelectedGroupService.self) private var selectedGroupService

    var item: PlayableContent

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
            play()
        } label: {
            HStack {
                ContentArtworkView(content: item)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                VStack(alignment: .leading) {
                    Text(item.title)
                        .lineLimit(1)
                    Text("\(item.content.type.title)\(item.subtitle.isEmpty ? "" : " • \(item.subtitle)")")
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
                Button {
                    play()
                } label: {
                    Text("Play")
                }

//                Button {
//                    play(position: .front, replaceQueue: true)
//                } label: {
//                    Text("Queue")
//                }

                NavigationLink(value: RouterDestination.mediaDetail(content: item, group: selectedGroupService.group)) {
                    Text("View")
                }

                if item.content.service == .library, item.content.id.last?.isNumber ?? false {
                    Button {
                        router.sheet(to: .renamePlaylist(content: item))
                    } label: {
                        Text("Rename")
                    }

                }
// TODO: Add scene playlist
//                NavigationLink(value: RouterDestination.createScene(content: item)) {
//                    Label("Create Scene", systemImage: "bolt.fill")
//                }

            case .album, .track, .libraryTrack:
                if [.album, .track].contains(item.content.type) {
                    NavigationLink(value: RouterDestination.mediaDetail(content: item, group: selectedGroupService.group)) {
                        Label("View Album", systemImage: "smallcircle.circle.fill")
                    }


                    NavigationLink(value: RouterDestination.artistDetail(content: item, group: selectedGroupService.group)) {
                        Label("View Artist", systemImage: "music.mic")
                    }

                    // TODO: Add scene playlist
//                    NavigationLink(value: RouterDestination.createScene(content: item)) {
//                        Label("Create Scene", systemImage: "bolt.fill")
//                    }
                }

                Button {
                    play()
                } label: {
                    Label("Play Now", systemImage: "play.fill")
                }

                Button {
                    play(position: .next)
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                Button {
                    play(position: .end)
                } label: {
                    Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
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
            guard let group = selectedGroupService.group else {
                router.navigate(to: .groupDestination(content: item, position: position))
                return
            }
            hideKeyboard()
            playHistoryService.history.remove(item)
            playHistoryService.history.insert(item, at: 0)
            alertService.showAlertContent(with: item)
            HapticManager.shared.fireHaptic(.buttonPress)
            await sonosService.queue(playable: item, group: group, position: position)
            await sonosService.play(ip: group.coordinatorRoom.ip)
            try? await Task.sleep(for: .milliseconds(100))
            try? await sonosService.updateGroups(from: [group])
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
