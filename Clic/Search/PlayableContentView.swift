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
    @CloudStorage(CloudKeys.playHistory) var playHistory: OrderedSet<PlayableContent> = []
    
    var item: PlayableContent
    var group: GroupRoom?

    var body: some View {
        switch item.content.type {
        case .playlist, .album:
            NavigationLink(value: RouterDestination.mediaDetail(content: item, group: group)) {
                content
            }
        case .artist:
            NavigationLink(value: RouterDestination.artistDetail(content: item, group: group)) {
                content
            }
        case .track, .favorite:
            content
        }
    }

    private func play(position: QueuePosition = .now) {
        Task {
            guard let group = group else {
                router.navigate(to: .groupDestination(content: item, position: position))
                return
            }
            playHistory.remove(item)
            playHistory.insert(item, at: 0)
            
            router.dismiss = true
            await sonosService.queue(content: item.content, group: group, position: position)
            await sonosService.play(ip: group.coordinatorRoom.ip)
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
                
// TODO: Add scene playlist
//                NavigationLink(value: RouterDestination.createScene(content: item)) {
//                    Label("Create Scene", systemImage: "bolt.fill")
//                }

            case .album, .track, .favorite:
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
                    Menu {
                        menu
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(maxWidth: 40, maxHeight: .infinity)
                            .background(.clear)
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
            menu
        }
        .draggable(item)
    }
}

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
