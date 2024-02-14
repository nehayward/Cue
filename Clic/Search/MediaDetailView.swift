import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import NukeUI
import VibesDS

struct MediaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router

    @CloudStorage(CloudKeys.playHistory) var playHistory: OrderedSet<PlayableContent> = []

    @State var playableContent: PlayableContent?
    @State var artworkURL: URL?

    let id: String
    let title: String
    let kind: MediaKind

    @State var album: Album? = nil
    @State var playlist: Playlist? = nil

    var group: GroupRoom?
    
    var body: some View {
        List {
            Group {
                LazyImage(url: artworkURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else if state.isLoading {
                        RoundedRectangle(cornerRadius: 4)
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.ultraThinMaterial)
                            .shadow(radius: 2)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 2)
                .scaledToFit()
                .frame(width: 300, height: 300)
            }
            .frame(maxWidth: .infinity)
            .listSectionSeparator(.hidden)
            if album != nil || playlist != nil {
                Section {
                    if let tracks = album?.tracks {
                        ForEach(tracks) { track in
                            let playableContent = PlayableContent(title: track.title, subtitle: track.artistName, artwork: track.artwork?.url(width: 100, height: 100), content: MediaContent(service: .apple, id: track.id.description, type: .track, location: track.url))
                            Button {
                                play(content: playableContent)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(track.title)
                                        Text(track.artistName)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Menu {
                                        menu(content: playableContent)
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .frame(maxWidth: 40, maxHeight: .infinity)
                                            .background(.clear)
                                    }
                                }
                                .contextMenu {
                                    menu(content: playableContent)
                                }
                            }
                        }
                    }
                    if let tracks = playlist?.tracks {
                        ForEach(tracks) { track in
                            let playableContent = PlayableContent(title: track.title, subtitle: track.artistName, artwork: track.artwork?.url(width: 100, height: 100), content: MediaContent(service: .apple, id: track.id.description, type: .track, location: track.url))

                            Button {
                                play(content: playableContent)
                            } label: {
                                HStack {
                                    ContentArtworkView(content: .constant(nil), artworkURL: track.artwork?.url(width: 100, height: 100))
                                        .frame(width: 44, height: 44)
                                    VStack(alignment: .leading) {
                                        Text(track.title)
                                        Text(track.artistName)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Menu {
                                        menu(content: playableContent)
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .frame(maxWidth: 40, maxHeight: .infinity)
                                            .background(.clear)
                                    }
                                }
                                .contextMenu {
                                    menu(content: playableContent)
                                }
                            }
                        }
                    }
                } header: {
                    Button {
                        switch kind {
                        case .album:
                            guard let album else { return }
                            let playableContent = PlayableContent(title: album.title, subtitle: album.artistName, artwork: album.artwork?.url(width: 100, height: 100), content: MediaContent(service: .apple, id: album.id.description, type: .album, location: nil))
                            play(content: playableContent)
                        case .playlist:
                            guard let playlist else { return }
                            let playableContent = PlayableContent(title: playlist.name, subtitle: playlist.curatorName ?? "", artwork: playlist.artwork?.url(width: 100, height: 100), content: MediaContent(service: .apple, id: playlist.id.description, type: .playlist, location: nil))
                            play(content: playableContent)
                        default:
                            break
                        }
                    } label: {
                        Text("Queue All")
                    }
                    .padding()
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .padding(.vertical)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .listStyle(.inset)
        .listSectionSeparator(.hidden)
        .navigationTitle(title)
        .task {
            //            artworkURL = URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/c0/54/97/c05497aa-c19f-bf4f-de29-71edf30fbefb/075679688767.jpg/1000x1000bb.jpg")
            switch kind {
            case .album:
                album = try? await MusicSearchService().lookup(id: id)
                artworkURL = album?.artwork?.url(width: 800, height: 800)
            case .playlist:
                playlist = try? await MusicSearchService().lookup(id: id)
                artworkURL = playlist?.artwork?.url(width: 800, height: 800)
            default:
                break
            }
        }
    }

    private func play(content: PlayableContent, position: QueuePosition = .now) {
        Task {
            playHistory.remove(content)
            playHistory.insert(content, at: 0)

            guard let group = group else {
                router.navigate(to: .groupDestination(content: content))
                return
            }
            router.dismiss = true
            await sonosService.queue(content: content.content, group: group, position: position)
            await sonosService.play(ip: group.coordinatorRoom.ip)
        }
    }

    private func menu(content: PlayableContent) -> some View {
        VStack {
            Button {
                play(content: content, position: .next)
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                play(content: content, position: .end)
            } label: {
                Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
        }
    }
}

#Preview {
    // https://music.apple.com/us/playlist/dua-lipa-essentials/pl.ee7b1aea4b5f42d398e6cd3084f7396b
    // https://music.apple.com/us/album/future-nostalgia-the-moonlight-edition/1551178998
    MediaDetailView(id: "1552269067", title: "Future Nostaliga", kind: .album)
        .environment(SonosService.shared)
        .environment(Router())
}

struct ViewOffsetKey: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue = CGFloat.zero
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value += nextValue()
    }
}
