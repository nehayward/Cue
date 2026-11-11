import SonosKit
import SwiftUI

/// A list as a grid, as the Music app draws its library: covers with the
/// title and artist under them (`PlayableCardView`), and artists as round
/// tiles with the name centred under them (`ArtistGridTile`), each picked
/// per item, so a mixed grid (Apple Music's Favorites) draws its artists
/// round too. The caller puts it in a scroll view; `onAppear` hears of each
/// tile as it shows, for paging.
struct PlayableGrid: View {
    let items: [PlayableContent]
    var onAppear: (PlayableContent) -> Void = { _ in }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.displayScale) private var displayScale
    @Environment(\.zoomNamespace) private var zoomNamespace

    /// Only artists: smaller tiles, as the Music app's artists.
    private var isArtists: Bool {
        !items.isEmpty && items.allSatisfy(\.content.type.isArtist)
    }

    private var columns: [GridItem] {
        if isArtists {
            return [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 16)]
        }
        // Two across a phone, more as the width grows, as the Music app's
        // album grid.
        return [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)]
    }

    /// The size every cover asks for — one tier per device class, not the
    /// tile's measured width. A phone's tiles are never wider than about
    /// 180pt, an iPad's or a Mac's never wider than the column's maximum,
    /// so a cover decoded at the tier is sharp in any tile the layout makes,
    /// while a window resize only lays out again: the same decoded bitmaps,
    /// never fetched or decoded again. The artwork view decodes at three
    /// pixels per point, a phone's density, so the tier is scaled down for
    /// a 2x screen.
    private var artworkSize: Double {
        let points: Double = sizeClass == .compact ? 180 : 220
        return points * min(displayScale, 3) / 3
    }

    var body: some View {
        let artworkSize = artworkSize
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            ForEach(items) { item in
                tile(for: item, artworkSize: artworkSize)
                    .onAppear { onAppear(item) }
            }
        }
    }

    /// With a zoom namespace from the root, an album's cover is what its
    /// screen zooms out of; without one it pushes plainly. Not on Catalyst,
    /// where the zoom transition doesn't animate and a source on every tile
    /// would be bookkeeping for nothing.
    @ViewBuilder
    private func tile(for item: PlayableContent, artworkSize: Double) -> some View {
        if item.content.type.isArtist {
            ArtistGridTile(item: item, artworkSize: artworkSize)
        } else {
#if targetEnvironment(macCatalyst)
            PlayableCardView(item: item, artworkSize: artworkSize, usesContextMenu: true)
#else
            PlayableCardView(
                item: item,
                artworkSize: artworkSize,
                usesContextMenu: true,
                zoomSource: zoomNamespace == nil ? nil : .album(item.id)
            )
#endif
        }
    }
}

/// An artist in a grid: a round picture with the name centred under it,
/// and the artist's menu on a long press (a right click on the Mac) rather
/// than a ••• over the picture.
struct ArtistGridTile: View {
    let item: PlayableContent
    var artworkSize: Double = 160

    @Environment(Router.self) private var router
    @Environment(SelectedGroupService.self) private var selectedGroupService

    var body: some View {
        Button {
            router.navigate(to: .artistDetail(content: item, group: selectedGroupService.group))
        } label: {
            VStack(spacing: 8) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ContentArtworkView(content: item, showMusicSource: false, preferredSize: artworkSize)
                            .scaledToFill()
                    }
                    .clipShape(.circle)
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .fontDesign(.rounded)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .contentShape(.rect)
            .largeWindowHoverLift()
        }
        .buttonStyle(.plain)
        .contentShape(.contextMenuPreview, .circle)
        .contextMenu {
            PlayableMenuView(item: item)
        }
    }
}
