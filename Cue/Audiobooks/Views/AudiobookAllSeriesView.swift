import MusicSearchKit
import SonosKit
import SwiftUI

extension AudiobookSeries {
    /// The servers' series, one a name (a series on both servers is one),
    /// those with two or more books, by name.
    static func merged(_ all: [AudiobookSeries]) -> [AudiobookSeries] {
        Dictionary(grouping: all) { $0.name.lowercased() }
            .compactMap { _, same in
                guard let first = same.first else { return nil }
                return AudiobookSeries(id: first.name.lowercased(), name: first.name, books: same.flatMap(\.books))
            }
            .filter { $0.books.count > 1 }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Every series of the servers the Audiobooks tab shows (`merged`):
    /// Plex's, from what Audible says of each book, and Audiobookshelf's.
    @MainActor
    static func shown(_ coreFeatures: CoreFeatures) -> [AudiobookSeries] {
        let plex = PlexBookShelf.shared
        let shelf = AudiobookshelfBrowseService.shared
        let plexBooks = coreFeatures.isEnabled(.plex) && plex.hasBooks ? plex.all : []
        let shelfSeries = coreFeatures.isEnabled(.audiobookshelf) && shelf.isAuthenticated ? shelf.series : []
        return merged(AudiobookLibrary.plexSeries(plexBooks) + shelfSeries)
    }
}

/// A series as a tile: its first books' covers stacked, its name and how
/// many books (and readings, when it's read more than once). The same on
/// the Audiobooks tab's shelf and on the page of every series.
struct AudiobookSeriesCard: View {
    let series: AudiobookSeries
    let size: CGFloat

    /// The shelf's tiles: bigger than its books' covers, as the stacked
    /// covers inside are drawn smaller than the tile.
    static let shelfSize: CGFloat = 160

    var body: some View {
        let narrations = AudiobookSeriesView.narrations(of: series.books)
        let lead = narrations.first?.books ?? series.books
        let count = narrations.map(\.books.count).max() ?? series.books.count
        VStack(alignment: .leading, spacing: 4) {
            AudiobookCoverStack(books: lead, size: size)
            Text(series.name)
                .font(.subheadline)
                .lineLimit(1)
            Text(narrations.count > 1 ? "^[\(count) book](inflect: true) · \(narrations.count) readings" : "^[\(count) book](inflect: true)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: size)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Every series the book servers have, as a grid of tiles by name, a tap
/// opening its page (`AudiobookSeriesView`). Read from the servers' shelves
/// as it draws, so Plex's series fill in as Audible answers for its books.
struct AudiobookAllSeriesView: View {
    @Environment(CoreFeatures.self) private var coreFeatures
    @Environment(Router.self) private var router
    @State private var width: CGFloat = 0

    private static let spacing: CGFloat = 16
    private static let margin: CGFloat = 16
    /// The narrowest a tile gets before a row has one fewer.
    private static let minimumTile: CGFloat = 150

    /// As many columns as fit tiles at least `minimumTile` wide, never
    /// fewer than two, and the tiles as wide as they then can be.
    private var columns: (count: Int, size: CGFloat) {
        let room = max(0, width - 2 * Self.margin)
        let count = max(2, Int((room + Self.spacing) / (Self.minimumTile + Self.spacing)))
        let size = (room - Self.spacing * CGFloat(count - 1)) / CGFloat(count)
        return (count, max(80, size.rounded(.down)))
    }

    var body: some View {
        let series = AudiobookSeries.shown(coreFeatures)
        let columns = columns
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(columns.size), spacing: Self.spacing, alignment: .top), count: columns.count),
                alignment: .leading,
                spacing: 22
            ) {
                ForEach(series) { series in
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        router.navigate(to: .audiobookSeries(name: series.name, books: series.books))
                    } label: {
                        AudiobookSeriesCard(series: series, size: columns.size)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Self.margin)
        }
        .contentMargins(.bottom, 120, for: .scrollContent)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .overlay {
            if series.isEmpty {
                ContentUnavailableView(
                    "No Series",
                    systemImage: "books.vertical",
                    description: Text("Series show here once a server has two or more books of one.")
                )
            }
        }
        .navigationTitle("Series")
        .toolbarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
    }
}
