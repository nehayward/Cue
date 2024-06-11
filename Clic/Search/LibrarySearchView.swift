import CloudStorage
import Defaults
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit

struct LibrarySearchView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss
    @Environment(Router.self) var router: Router

    var librarySearchResults: [PlayableContent]
    @Binding var filters: [FilterSelection]

    var group: GroupRoom?

    var body: some View {
        Group {
            if filters.filter(\.isFiltered).isEmpty {
                ForEach(librarySearchResults) { item in
                    PlayableContentView(item: item, group: group)
                }
            } else {
                ForEach(librarySearchResults) { item in
                    if filters.filter(\.isFiltered).map(\.filter.toContentType).contains(item.content.type) {
                        PlayableContentView(item: item, group: group)
                    }
                }
            }
        }
        .animation(.bouncy, value: filters)
        .animation(.bouncy, value: librarySearchResults)
        .fontDesign(.rounded)

    }
}
