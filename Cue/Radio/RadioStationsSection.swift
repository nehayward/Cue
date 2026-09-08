import SonosKit
import SwiftUI

/// One row of the Radio tab: a titled run of stations in a two-column
/// grid, headed by a link to the full list. The same shape Sonos Radio's
/// browse screen uses for its curated rows, so a station reads the same
/// whichever source it came from.
struct RadioStationsSection: View {
    let title: String
    /// Where the stations come from — "TuneIn", "Apple Music" — under the
    /// title, since the tab mixes sources that each have their own rows.
    var caption: String? = nil
    let items: [PlayableContent]
    /// The full list the title opens.
    let seeAll: RouterDestination
    /// Stations shown in the grid before the "see all" link.
    var previewCount = 6

    var body: some View {
        Section {
            NavigationLink(value: seeAll) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontDesign(.rounded)
                        .fontWeight(.semibold)
                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            LazyVGrid(columns: [.init(), .init()]) {
                ForEach(items.prefix(previewCount)) { item in
                    PlayableContentRowView(item: item)
                        .buttonStyle(.plain)
                        .geometryGroup()
                }
            }
        }
        .listRowInsets(.default)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowSpacing(0)
    }
}
