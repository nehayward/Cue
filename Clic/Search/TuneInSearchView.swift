import SwiftUI
import MusicSearchKit
import SonosKit

struct TuneInSearchView: View {
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(SonosService.self) private var sonosService
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router

    let tuneInResults: [PlayableContent]
    @Binding var filters: [FilterSelection]

    private var filteredResults: [PlayableContent] {
        guard !filters.filter(\.isFiltered).isEmpty else {
            return tuneInResults
        }
        
        let activeContentTypes = Set(filters.filter(\.isFiltered).flatMap(\.filter.toContentType))
        return tuneInResults.filter { activeContentTypes.contains($0.content.type) }
    }

    var body: some View {
        ForEach(filteredResults) { item in
            VStack {
                PlayableContentView(item: item)
            }
        }
        .fontDesign(.rounded)
    }
}
