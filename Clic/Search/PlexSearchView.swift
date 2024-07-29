import CloudStorage
import Defaults
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit

struct PlexSearchView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router

    var plexResults: [PlayableContent]
    @Binding var filters: [FilterSelection]

    var body: some View {
        PlexAuthorizationFlowView()
        ForEach(plexResults) { item in
            if filters.filter(\.isFiltered).isEmpty {
                PlayableContentView(item: item)
            } else {
                if filters.filter(\.isFiltered).map(\.filter.toContentType).contains(item.content.type) {
                    PlayableContentView(item: item)
                }
            }
        }
        .fontDesign(.rounded)
    }
}
