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
                        VStack(alignment: .leading, spacing: 4) {
                            ContentArtworkView(content: book, showMusicSource: false, preferredSize: 300, cornerRadius: 6)
                                .frame(width: Self.coverSize, height: Self.coverSize)
                            Text(book.title)
                                .font(.footnote)
                                .lineLimit(1)
                            Text(book.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: Self.coverSize)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        AudiobookMenuItems(book: book)
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
}
