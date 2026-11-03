import SonosKit
import SwiftUI

/// The Apple Library's playlists, personal stations and recommended albums
/// as tiles, a cover with the title under it, in a grid that flows with
/// the window as Recently Added's does: as many columns as fit, two rows
/// at most. Cards that split the row grew to a third of a wide window
/// each; a tile is at least 140 points, 12 apart.
///
/// A list row of its own, with its own insets: the tiles line up with the
/// section's header.
struct TileGrid: View {
    let items: [PlayableContent]

    /// Enough to fill two rows of a wide Mac window: what a section loads
    /// for its tiles.
    static let fillCount = 24

    @Environment(\.usesPadLayout) private var usesPadLayout

    var body: some View {
        // A library playlist has no curator, so most have no subtitle: a
        // line for it only when one does, kept on every tile so the rows
        // stay in line.
        let showsSubtitle = items.contains { !$0.subtitle.isEmpty }
        // An iPhone's width doesn't change as it's used, so its two columns
        // grow to fill it; an iPad's or the Mac's window is resized live,
        // and its tiles keep their size (`TwoRowGrid`).
        TwoRowGrid(minimumTileWidth: 140, spacing: 12, rowSpacing: 16, fillsWidth: !usesPadLayout) {
            ForEach(items) { item in
                PlayableCardView(item: item, artworkSize: 180, isTile: true, tileShowsSubtitle: showsSubtitle)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// Tiles of one size and spacing in as many columns as fit, in two rows at
/// most: with `fillsWidth`, the tiles grow to fill the row, else they keep
/// `minimumTileWidth` and the room left over is at the trailing end. A
/// second row less than half full is left off (11 playlists and one more
/// under them), the section's header opening the rest.
///
/// A layout, so the column count comes from the width it's offered on each
/// pass, as a `LazyVGrid`'s adaptive columns do: a width measured into
/// state and fed back into a self-sizing list cell can loop
/// (`PlayableContentGridView`), and a `ViewThatFits` that tried a second
/// layout hitched every step of a window resize. Without `fillsWidth`
/// nothing moves as a window resizes but a column coming or going: tiles
/// that grew with the width laid out their text again on every step and
/// changed the row's height, which the list followed a step behind, and
/// gaps that grew to fill the row moved every tile, both jittering. Tiles
/// not shown are placed out of sight, far past the trailing edge, where
/// neither the list nor a click reaches.
private struct TwoRowGrid: Layout {
    var minimumTileWidth: CGFloat
    var spacing: CGFloat
    var rowSpacing: CGFloat
    var fillsWidth: Bool

    private func columns(in width: CGFloat) -> Int {
        max(1, Int((width + spacing) / (minimumTileWidth + spacing)))
    }

    private func tileWidth(in width: CGFloat, columns: Int) -> CGFloat {
        guard fillsWidth else { return minimumTileWidth }
        return (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    /// Every tile is one height: one line of title, and a subtitle on all
    /// of them or none.
    private func tileHeight(_ subviews: Subviews, tileWidth: CGFloat) -> CGFloat {
        subviews.first?.sizeThatFits(ProposedViewSize(width: tileWidth, height: nil)).height ?? 0
    }

    /// How many tiles show: two rows at most, the second only when at
    /// least half full.
    private func shownCount(_ subviews: Subviews, columns: Int) -> Int {
        let second = min(subviews.count, columns * 2) - columns
        guard second > 0 else { return subviews.count }
        return second * 2 >= columns ? columns + second : columns
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Asked for its ideal size, one row of every tile.
        let width = proposal.width ?? CGFloat(subviews.count) * (minimumTileWidth + spacing) - spacing
        let columns = self.columns(in: width)
        let rows = (shownCount(subviews, columns: columns) + columns - 1) / columns
        let tileHeight = self.tileHeight(subviews, tileWidth: tileWidth(in: width, columns: columns))
        let height = CGFloat(rows) * tileHeight + rowSpacing * CGFloat(max(rows - 1, 0))
        return CGSize(width: width, height: height)
    }

    // No alignment guides of its own: the default merges every tile's,
    // measuring each one on every pass of a resize.
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? {
        nil
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? {
        nil
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = self.columns(in: bounds.width)
        let shown = shownCount(subviews, columns: columns)
        let tileWidth = self.tileWidth(in: bounds.width, columns: columns)
        let rowHeight = tileHeight(subviews, tileWidth: tileWidth) + rowSpacing
        let tileProposal = ProposedViewSize(width: tileWidth, height: nil)
        for (index, tile) in subviews.enumerated() {
            guard index < shown else {
                tile.place(at: CGPoint(x: bounds.maxX + 10_000, y: bounds.minY), proposal: .zero)
                continue
            }
            tile.place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(index % columns) * (tileWidth + spacing),
                    y: bounds.minY + CGFloat(index / columns) * rowHeight
                ),
                proposal: tileProposal
            )
        }
    }
}
