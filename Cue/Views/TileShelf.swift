import SonosKit
import SwiftUI

/// Covers in two rows, filled column by column, scrolling sideways: the
/// Apple Library's playlists, personal stations and recommended albums.
/// The tiles are a fixed size, so a wide window shows more of them, where
/// cards that split the row grew to a third of the window each. Two rows
/// only when there are enough for both to run across the shelf, else one:
/// 12 playlists in two rows stopped halfway across a wide window, beside
/// shelves that ran off its edge.
///
/// A list row of its own, with its own insets: the covers line up with
/// the section's header and scroll on to the list's edges.
struct TileShelf: View {
    let items: [PlayableContent]

    /// Enough to fill two rows of a wide Mac window: what a section loads
    /// for its shelf.
    static let fillCount = 20

    private static let tileWidth: CGFloat = 140
    private static let spacing: CGFloat = 12
    private static let margin: CGFloat = 16

    /// The shelf's width, to tell whether the items fill two rows.
    @State private var width: CGFloat = 0

    var body: some View {
        let fits = width > 0 ? Int((width - Self.margin * 2 + Self.spacing) / (Self.tileWidth + Self.spacing)) : 6
        let rows = items.count >= max(fits, 2) * 2 ? 2 : 1
        let columns = stride(from: 0, to: items.count, by: rows).map {
            Array(items[$0..<min($0 + rows, items.count)])
        }
        // A library playlist has no curator, so most have no subtitle: a
        // line for it only when one does, kept on every tile so the rows
        // stay in line.
        let showsSubtitle = items.contains { !$0.subtitle.isEmpty }
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Self.spacing) {
                ForEach(columns, id: \.[0].id) { column in
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(column) { item in
                            PlayableCardView(item: item, tileWidth: Self.tileWidth, tileShowsSubtitle: showsSubtitle)
                        }
                    }
                }
            }
        }
        // Margins, not padding, so the covers settle in line with the
        // header and scroll on to the list's edges.
        .contentMargins(.horizontal, Self.margin, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
