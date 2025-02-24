import CloudStorage
import Defaults
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit

struct LibrarySearchView: View {
    @Environment(\.dismiss) var dismiss

    @Environment(SonosService.self) private var sonosService: SonosService
    @Environment(Router.self) private var router: Router

    var librarySearchResults: [PlayableContent]
    @Binding var filters: [FilterSelection]

    var body: some View {
        Group {
            if filters.filter(\.isFiltered).isEmpty {
                ForEach(librarySearchResults) { item in
                    VStack {
                        PlayableContentView(item: item)
                    }
                }
            } else {
                ForEach(librarySearchResults) { item in
                    if filters.filter(\.isFiltered).flatMap(\.filter.toContentType).contains(item.content.type) {
                        VStack {
                            PlayableContentView(item: item)
                        }
                    }
                }
            }
        }
        .animation(.bouncy, value: filters)
        .animation(.bouncy, value: librarySearchResults)
        .fontDesign(.rounded)
    }
}
