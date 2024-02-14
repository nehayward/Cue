import CloudStorage
import MusicSearchKit
import Defaults
import NukeUI
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults

struct AppleMusicSearchScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(Router.self) private var router

    @CloudStorage(CloudKeys.playHistory) var playHistory: OrderedSet<PlayableContent> = []

    let result: MusicCatalogSearchSuggestionsResponse.TopResult
    @Binding var filters: [FilterSelection]

    var group: GroupRoom?

    var body: some View {
        if filters.filter(\.isFiltered).isEmpty {
            switch result {
            case .album:
                album(result)
            case .artist:
                artist(result)
            case .playlist:
                playlist(result)
            case .song:
                songs(result)
            default:
                EmptyView()
            }
        } else {
            ForEach(filters.filter(\.isFiltered)) { filter in
                switch filter.filter {
                case .albums:
                    album(result)
                case .artist:
                    artist(result)
                case .songs:
                    songs(result)
                case .playlists:
                    playlist(result)
                }
            }
            .animation(.bouncy, value: filters)
            .fontDesign(.rounded)
        }
    }

    @ViewBuilder
    private func artist(_ result: MusicCatalogSearchSuggestionsResponse.TopResult) -> some View {
//        if case let .artist(artist) = result {
//            HStack {
//                ContentArtworkView(content: .constant(nil), artworkURL: result.artwork?.url(width: 100, height: 100))
//                    .frame(width: 44, height: 44)
//                    .clipShape(Circle())
//                VStack(alignment: .leading) {
//                    Text(artist.name)
//                }
//            }
//        } else {
            EmptyView()
//        }
    }

    @ViewBuilder
    private func playlist(_ result: MusicCatalogSearchSuggestionsResponse.TopResult) -> some View {
        if case let .playlist(playlist) = result {
            NavigationLink(value: RouterDestination.mediaDetail(id: playlist.id.description, title: playlist.name, kind: .playlist, group: group)) {
                HStack {
                    ContentArtworkView(content: .constant(nil), artworkURL: playlist.artwork?.url(width: 100, height: 100))
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading) {
                        Text(playlist.name)
                        Text(playlist.curatorName ?? "")
                            .lineLimit(1, reservesSpace: true)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func songs(_ result: MusicCatalogSearchSuggestionsResponse.TopResult) -> some View {
        if case let .song(song) = result {
            let playableContent = PlayableContent(title: song.title, subtitle: song.artistName, artwork: song.artwork?.url(width: 100, height: 100), content: MediaContent(service: .apple, id: song.id.description, type: .track, location: song.url))
            Button {
                play(content: playableContent)
            } label: {
                HStack {
                    ContentArtworkView(content: .constant(nil), artworkURL: song.artwork?.url(width: 100, height: 100))
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading) {
                        Text(song.title)
                        Text(song.artistName)
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
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func album(_ result: MusicCatalogSearchSuggestionsResponse.TopResult) -> some View {
        if case let .album(album) = result {
            NavigationLink(value: RouterDestination.mediaDetail(id: album.id.description, title: album.title, kind: .album, group: group)) {
                HStack {
                    ContentArtworkView(content: .constant(nil), artworkURL: album.artwork?.url(width: 100, height: 100))
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading) {
                        Text(album.title)
                        Text(album.artistName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            EmptyView()
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
