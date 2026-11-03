import SonosKit
import SwiftUI

/// The Apple Library's playlists, personal stations and recommended albums
/// as tiles, a cover with the title under it, in a grid that flows with
/// the window as Recently Added's does: as many columns as fit, two rows
/// at most. Cards that split the row grew to a third of a wide window
/// each; a tile is always 140 points.
///
/// A list row of its own, with its own insets: the tiles line up with the
/// section's header.
struct TileGrid: View {
    let items: [PlayableContent]

    /// Enough to fill two rows of a wide Mac window: what a section loads
    /// for its tiles.
    static let fillCount = 24

    var body: some View {
        // A library playlist has no curator, so most have no subtitle: a
        // line for it only when one does, kept on every tile so the rows
        // stay in line.
        let showsSubtitle = items.contains { !$0.subtitle.isEmpty }
        TwoRowGrid(tileWidth: 140, minimumSpacing: 12, rowSpacing: 16) {
            ForEach(items) { item in
                PlayableCardView(item: item, artworkSize: 140, isTile: true, tileShowsSubtitle: showsSubtitle)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// Tiles of one size in as many columns as fit, the room left over shared
/// between the columns so they run edge to edge, in two rows at most.
///
/// A layout, so the column count comes from the width it's offered on each
/// pass, as a `LazyVGrid`'s adaptive columns do: a width measured into
/// state and fed back into a self-sizing list cell can loop
/// (`PlayableContentGridView`), and a `ViewThatFits` that tried a second
/// layout hitched every step of a window resize. The tiles keep their
/// size, so a resize only moves them: tiles that grew with the width laid
/// out their text again on every step, and the row's height changed with
/// it, which the list followed a step behind, jittering. Tiles past the
/// second row are placed out of sight, far past the trailing edge, where
/// neither the list nor a click reaches.
private struct TwoRowGrid: Layout {
    var tileWidth: CGFloat
    var minimumSpacing: CGFloat
    var rowSpacing: CGFloat

    private var tileProposal: ProposedViewSize {
        ProposedViewSize(width: tileWidth, height: nil)
    }

    private func columns(in width: CGFloat) -> Int {
        max(1, Int((width + minimumSpacing) / (tileWidth + minimumSpacing)))
    }

    private func spacing(in width: CGFloat, columns: Int) -> CGFloat {
        columns > 1 ? (width - tileWidth * CGFloat(columns)) / CGFloat(columns - 1) : 0
    }

    /// Every tile is one height: one line of title, and a subtitle on all
    /// of them or none.
    private func tileHeight(_ subviews: Subviews) -> CGFloat {
        subviews.first?.sizeThatFits(tileProposal).height ?? 0
    }

    private func rowCount(_ subviews: Subviews, columns: Int) -> Int {
        min(2, (subviews.count + columns - 1) / columns)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Asked for its ideal size, one row of every tile.
        let width = proposal.width ?? CGFloat(subviews.count) * (tileWidth + minimumSpacing) - minimumSpacing
        let rows = rowCount(subviews, columns: columns(in: width))
        let height = CGFloat(rows) * tileHeight(subviews) + rowSpacing * CGFloat(max(rows - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = self.columns(in: bounds.width)
        let spacing = self.spacing(in: bounds.width, columns: columns)
        let rowHeight = tileHeight(subviews) + rowSpacing
        for (index, tile) in subviews.enumerated() {
            guard index < columns * 2 else {
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
