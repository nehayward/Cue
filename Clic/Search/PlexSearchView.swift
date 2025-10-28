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
    @Binding var plexLibrariesFilters: [GenericFilter<PlexLibrarySection>]

    // MARK: - Computed Properties
    
    private var filteredResults: [PlayableContent] {
        let activeFilters = filters.filter(\.isFiltered)
        
        // Get filtered library IDs
        let filteredLibraryIDs = Set(
            plexLibrariesFilters
                .filter(\.isFiltered)
                .compactMap { $0.filter.key }
        )
        
        // Start with all results
        var results = plexResults
        
        // Apply library filters if any are active
        if !filteredLibraryIDs.isEmpty {
            results = results.filter {
                guard let id = $0.metadata?.librarySectionID else { return false }
                return filteredLibraryIDs.contains(id)
            }
        }
        
        // Apply content type filters if any are active
        if !activeFilters.isEmpty {
            let filteredContentTypes = Set(activeFilters.flatMap(\.filter.toContentType))
            
            results = results.filter { item in
                filteredContentTypes.isEmpty || filteredContentTypes.contains(item.content.type)
            }
        }
        
        return results
    }
    // MARK: - Body
    
    var body: some View {
        ForEach(filteredResults) { item in
            PlayableContentView(item: item)
        }
        .fontDesign(.rounded)
        
        PlexLibrarySelectionView()
    }
}
