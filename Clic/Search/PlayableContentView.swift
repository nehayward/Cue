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

    @CloudStorage(CloudKeys.playHistory) var playHistory: OrderedSet<PlayableContent> = []
    @State var playlists: [PlayableContent] = []

    var item: PlayableContent
    var group: GroupRoom?

    var body: some View {
        // MARK: Adding Content View
        if let add = adding?.add, add {
            content
        } else {
            switch item.content.type {
            case .playlist, .album:
                NavigationLink(value: RouterDestination.mediaDetail(content: item, group: group)) {
                    content
                }
            case .artist:
                NavigationLink(value: RouterDestination.artistDetail(content: item, group: group)) {
                    content
                }
            case .track, .favorite, .radio:
                content
            }
        }
    }

    private var content: some View {
        Button {
            play()
        } label: {
            HStack {
                ContentArtworkView(content: .constant(item))
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
                                .frame(maxWidth: 40, maxHeight: .infinity)
                                .background(.clear)
                        }
                    }
                default:
                    EmptyView()
                }
            }
            .fontDesign(.rounded)
        }
        // MARK: SwiftUI Issues
//        .swipeActions {
//            if playHistory.contains(item) {
//                Button(role: .destructive) {
//                    playHistory.remove(item)
//                } label: {
//                    Label("Remove from History", systemImage: "trash")
//                }
//            }
//        }
        .contentShape(.contextMenuPreview, Capsule())
        .contextMenu {
            if adding == nil {
                menu
            }
        }
        .draggable(item)
        .task {
            playlists = await sonosService.sonosPlaylists()
        }
    }


    private var menu: some View {
        VStack {
            if playHistory.contains(item) {
                Button(role: .destructive) {
                    playHistory.remove(item)
                } label: {
                    Label("Remove from History", systemImage: "trash")
                }
            }
            switch item.content.type {
            case .artist:
                NavigationLink(value: RouterDestination.artistDetail(content: item, group: group)) {
                    Label("View Artist", systemImage: "music.mic.circle.fill")
                }
            case .playlist:
                Button {
                    play()
                } label: {
                    Text("Play Playlist")
                }

                NavigationLink(value: RouterDestination.mediaDetail(content: item, group: group)) {
                    Text("View Playlist")
                }

                if item.content.service == .library {
                    Button {
                        router.presentedSheet = .renamePlaylist(content: item)
                    } label: {
                        Text("Rename")
                    }

                }
// TODO: Add scene playlist
//                NavigationLink(value: RouterDestination.createScene(content: item)) {
//                    Label("Create Scene", systemImage: "bolt.fill")
//                }

            case .album, .track:
                if [.album, .track].contains(item.content.type) {
                    NavigationLink(value: RouterDestination.mediaDetail(content: item, group: group)) {
                        Label("View Album", systemImage: "rectangle.stack.fill")
                    }


                    NavigationLink(value: RouterDestination.artistDetail(content: item, group: group)) {
                        Label("View Artist", systemImage: "music.mic.circle.fill")
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

                Menu("Add to Playlist") {
                    ForEach(playlists) { playlist in
                        Button(playlist.title) {
                            Task {
                                await sonosService.addToPlaylist(playlistID: playlist.id, playableContent: item)
                            }
                        }
                    }
                }
            case .radio, .favorite:
                Button {
                    play()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
            }
        }
    }

    private func play(position: QueuePosition = .now) {
        if let add = adding?.add, add {
            adding?.content = item
            router.dismiss = true
            return
        }
        Task {
            guard let group = group else {
                router.navigate(to: .groupDestination(content: item, position: position))
                return
            }
            playHistory.remove(item)
            playHistory.insert(item, at: 0)
            alertService.showAlertContent(with: item)
            HapticManager.shared.fireHaptic(.buttonPress)
            await sonosService.queue(playable: item, group: group, position: position)
            await sonosService.play(ip: group.coordinatorRoom.ip)
        }
    }
}

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
