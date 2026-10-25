import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// Books as a sideways row of covers with their titles, each opening its
/// page.
struct AudiobookCoverRow: View {
    let books: [PlayableContent]

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(books) { book in
                    NavigationLink(value: RouterDestination.audiobookDetail(content: book)) {
                        Self.tile(book, size: Self.coverSize)
                    }
                    .buttonStyle(.plain)
                    // The book alone as the menu's preview: a list lifts its
                    // whole row for a menu in it, which here was the shelf
                    // with every book on it.
                    .contextMenu {
                        AudiobookMenuItems(book: book)
                    } preview: {
                        Self.tile(book, size: 200)
                            .padding(12)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }

    static let coverSize: CGFloat = 120

    /// The cover, with the title and author under it.
    private static func tile(_ book: PlayableContent, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ContentArtworkView(content: book, showMusicSource: false, preferredSize: 300, cornerRadius: 6)
                .frame(width: size, height: size)
            Text(book.title)
                .font(.footnote)
                .lineLimit(1)
            Text(book.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: size)
    }
}
