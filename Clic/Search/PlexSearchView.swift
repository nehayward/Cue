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
        results.filteredByPlexLibraries(plexLibrariesFilters).filtered(by: filters)
    }

    var body: some View {
        ForEach(filteredResults) { item in
            PlayableContentView(item: item)
        }
        .fontDesign(.rounded)

        PlexLibrarySelectionView()
    }
}

extension [PlayableContent] {
    /// Applies the per-library Plex filter to a (possibly mixed-service)
    /// list: items from other services pass through untouched, so the merged
    /// multiservice list can honor the filter too. Playlists span libraries
    /// and have no `librarySectionID`, so they bypass the filter.
    func filteredByPlexLibraries(_ libraryFilters: [GenericFilter<PlexLibrarySection>]) -> [PlayableContent] {
        let filteredLibraryIDs = Set(
            libraryFilters
                .filter(\.isFiltered)
                .compactMap { $0.filter.key }
        )
        guard !filteredLibraryIDs.isEmpty else { return self }

        return filter { item in
            guard item.content.service == .plex else { return true }
            if item.content.type == .playlist { return true }
            guard let id = item.metadata?.librarySectionID else { return false }
            return filteredLibraryIDs.contains(id)
        }
    }
}
