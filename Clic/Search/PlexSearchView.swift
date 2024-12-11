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

    @Binding var query: String
    
    var plexResults: [PlayableContent]
    @Binding var filters: [FilterSelection]

    var body: some View {
        PlexAuthorizationFlowView {
            Task {
                let query = query
                self.query += " "
                try? await Task.sleep(for: .milliseconds(400))
                self.query = query
            }
        }
        ForEach(plexResults) { item in
            if filters.filter(\.isFiltered).isEmpty {
                PlayableContentView(item: item)
            } else {
                if filters.filter(\.isFiltered).flatMap(\.filter.toContentType).contains(item.content.type) {
                    PlayableContentView(item: item)
                }
            }
        }
        .fontDesign(.rounded)
    }
}
