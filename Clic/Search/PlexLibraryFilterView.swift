import Foundation
import SonosKit
import SwiftUI
import MusicSearchKit

struct PlexLibraryFilterView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(MusicSearchService.self) var musicSearchService

    @Binding var plexLibrariesFilters: [GenericFilter<PlexLibrarySection>]
    
    private var hasActiveFilters: Bool {
        plexLibrariesFilters.contains { $0.isFiltered }
    }

    var body: some View {
        Menu {
            ForEach(plexLibrariesFilters) { library in
                @Bindable var library = library
                Toggle(isOn: $library.isFiltered) {
                    Text(library.filter.name)
                }
                .menuActionDismissBehavior(.disabled)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal.decrease")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(hasActiveFilters ? AnyShapeStyle(.accent.gradient) : AnyShapeStyle(.primary))
            }
            .allowsHitTesting(false)
        }
        .buttonBorderShape(.circle)
        .glassButton()
        .id(plexLibrariesFilters.count)
    }
}
