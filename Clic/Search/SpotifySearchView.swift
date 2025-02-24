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

    var spotifyResults: [PlayableContent]
    @Binding var filters: [FilterSelection]

    var group: GroupRoom?

    var body: some View {
        let filteredResults = filters.filter(\.isFiltered).isEmpty ?
        spotifyResults :
        spotifyResults.filter { item in
            filters.filter(\.isFiltered).flatMap(\.filter.toContentType).contains(item.content.type)
        }

        Group {
            ForEach(filteredResults) { item in
                VStack {
                    PlayableContentView(item: item)
                }
            }
        }
        .animation(.bouncy, value: filters)
        .animation(.bouncy, value: spotifyResults)
        .fontDesign(.rounded)
    }
}
