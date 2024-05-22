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
    @CloudStorage(CloudKeys.playHistory) var playHistory: OrderedSet<PlayableContent> = []

    var plexResults: [PlayableContent]
    @Binding var filters: [FilterSelection]

    var group: GroupRoom?

    var body: some View {
        Group {
            if filters.filter(\.isFiltered).isEmpty {
                ForEach(plexResults) { item in
                    PlayableContentView(item: item, group: group)
                }
            } else {
                ForEach(plexResults) { item in
                    if filters.filter(\.isFiltered).map(\.filter.toContentType).contains(item.content.type) {
                        PlayableContentView(item: item, group: group)
                    }
                }
            }
        }
        .fontDesign(.rounded)
    }
}
