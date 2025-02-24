import CloudStorage
import Defaults
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit

struct TidalSearchView: View {
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss
    @Environment(Router.self) var router: Router

    var tidalResults: [PlayableContent]
    @Binding var filters: [FilterSelection]

    var body: some View {
        let filteredResults = filters.filter(\.isFiltered).isEmpty ?
        tidalResults :
        tidalResults.filter { item in
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
        .animation(.bouncy, value: tidalResults)
        .fontDesign(.rounded)
    }
}
