import CloudStorage
import Defaults
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit

struct SpotifySearchView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss
    @Environment(Router.self) var router: Router

    @CloudStorage(CloudKeys.playHistory) var playHistory: OrderedSet<PlayableContent> = []

    @Binding var spotifyResults: [PlayableContent]
    @Binding var filters: [FilterSelection]

    var group: GroupRoom?

    var body: some View {
        Group {
            if filters.filter(\.isFiltered).isEmpty {
                ForEach(spotifyResults) { item in
                    PlayableContentView(item: item, group: group)
                }
            } else {
                ForEach(spotifyResults) { item in
                    if filters.filter(\.isFiltered).map(\.filter.toContentType).contains(item.content.type) {
                        PlayableContentView(item: item, group: group)
                    }
                }
            }
        }
        .animation(.bouncy, value: filters)
        .animation(.bouncy, value: spotifyResults)
        .fontDesign(.rounded)
    }
}
