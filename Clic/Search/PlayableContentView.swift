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
                router.navigate(to: .groupDestination(content: item))
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
                Button {
                    router.path.append(.artistDetail(content: item, group: group))
                } label: {
                    Text("View Artist")
                }
            case .playlist:
                Button {
                    router.path.append(.mediaDetail(content: item, group: group))
                } label: {
                    Text("View Playlist")
                }

                Button {
                    play()
                } label: {
                    Text("Play Playlist")
                }
            case .album, .track, .favorite:
                if [.album, .track].contains(item.content.type) {
                    Button {
                        router.path.append(.mediaDetail(content: item, group: group))
                    } label: {
                        Label("View Album", systemImage: "rectangle.stack.fill")
                    }
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
                    Text("\(item.content.type.title)\(item.subtitle.isEmpty ? "" : " • \(item.subtitle)")")
                        .foregroundStyle(.secondary)
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
    }
}

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
