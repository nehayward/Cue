import CloudStorage
import Defaults
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit

struct PlexSearchView: View {
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss
    @Environment(Router.self) var router: Router

    var plexResults: [PlayableContent]
    @Binding var filters: [FilterSelection]

    var group: GroupRoom?

    var body: some View {
        ForEach(plexResults) { item in
            if filters.filter(\.isFiltered).isEmpty {
                PlayableContentView(item: item, group: group)
            } else {
                if filters.filter(\.isFiltered).map(\.filter.toContentType).contains(item.content.type) {
                    PlayableContentView(item: item, group: group)
                }
            }
        }
        .fontDesign(.rounded)
    }
}
