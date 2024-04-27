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
            Group {
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
            }
            .fontDesign(.rounded)
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
        if case let .artist(artist) = result {
            PlayableContentView(item: artist.toPlayable, group: group)
        }
    }

    @ViewBuilder
    private func playlist(_ result: MusicCatalogSearchSuggestionsResponse.TopResult) -> some View {
        if case let .playlist(playlist) = result {
            PlayableContentView(item: playlist.toPlayable, group: group)
        }
    }

    @ViewBuilder
    private func songs(_ result: MusicCatalogSearchSuggestionsResponse.TopResult) -> some View {
        if case let .song(song) = result {
            PlayableContentView(item: song.toPlayable, group: group)
        }
    }

    @ViewBuilder
    private func album(_ result: MusicCatalogSearchSuggestionsResponse.TopResult) -> some View {
        if case let .album(album) = result {
            PlayableContentView(item: album.toPlayable, group: group)
        }
    }
}
