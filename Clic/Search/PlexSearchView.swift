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
            
            // If library filters are set, use those exclusively
            if !filteredLibraryIDs.isEmpty {
                return plexResults.filter {
                    guard let id = $0.metadata?.librarySectionID else { return false }
                    return filteredLibraryIDs.contains(id)
                }
            }
            
            // Otherwise, filter by content types
            if !activeFilters.isEmpty {
                let filteredContentTypes = Set(activeFilters.flatMap(\.filter.toContentType))
                
                return plexResults.filter { item in
                    filteredContentTypes.isEmpty || filteredContentTypes.contains(item.content.type)
                }
            }
            
            // No filters active, return all results
            return plexResults
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
