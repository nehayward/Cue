import MusicSearchKit
import SwiftUI
import SonosKit

struct PlexSearchView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router

    @Binding var query: String

    var results: [PlayableContent]
    @Binding var filters: [FilterSelection]
    @Binding var plexLibrariesFilters: [GenericFilter<PlexLibrarySection>]

    private var filteredResults: [PlayableContent] {
        let filteredLibraryIDs = Set(
            plexLibrariesFilters
                .filter(\.isFiltered)
                .compactMap { $0.filter.key }
        )

        // Playlists span libraries and have no librarySectionID, so they bypass the library filter.
        let libraryFiltered: [PlayableContent]
        if filteredLibraryIDs.isEmpty {
            libraryFiltered = results
        } else {
            libraryFiltered = results.filter { item in
                if item.content.type == .playlist { return true }
                guard let id = item.metadata?.librarySectionID else { return false }
                return filteredLibraryIDs.contains(id)
            }
        }

        return libraryFiltered.filtered(by: filters)
    }

    var body: some View {
        ForEach(filteredResults) { item in
            PlayableContentView(item: item)
        }
        .fontDesign(.rounded)

        PlexLibrarySelectionView()
    }
}
