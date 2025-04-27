import CloudStorage
import Defaults
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit

struct ServiceSearchView: View {
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    
    @Environment(\.dismiss) var dismiss

    var results: [PlayableContent]
    @Binding var filters: [FilterSelection]

    var body: some View {
        let filteredResults = filters.filter(\.isFiltered).isEmpty ?
        results :
        results.filter { item in
            filters.filter(\.isFiltered).flatMap(\.filter.toContentType).contains(item.content.type)
        }

        ForEach(filteredResults) { item in
            VStack {
                PlayableContentView(item: item)
            }
        }
    }
}
