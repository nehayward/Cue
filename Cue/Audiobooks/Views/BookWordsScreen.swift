import SonosKit
import SwiftUI

/// Every word looked up in a book's transcript (`BookWordLookups`), by
/// book, the one looked up in last first: each word over the words around
/// it, a tap showing its meaning again, and held, Play from Here, Copy and
/// Remove. A search finds a word, or the words around it. A book's heading
/// opens its page. Opened from Words on the Audiobooks tab.
struct BookWordsScreen: View {
    @State private var lookups = BookWordLookups.shared
    @State private var search = ""

    var body: some View {
        let shelves = lookups.shelves(matching: search)
        List {
            ForEach(shelves) { shelf in
                Section {
                    ForEach(shelf.lookups) { lookup in
                        BookWordRow(lookup: lookup, book: shelf.book)
                    }
                } header: {
                    BookWordsHeading(book: shelf.book)
                }
            }
        }
        .overlay {
            if shelves.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView(
                        "No Words Yet",
                        systemImage: "character.book.closed",
                        description: Text("Tap a word in a book's transcript to look it up, and it's kept here.")
                    )
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
        .searchable(text: $search, prompt: "Words")
        .navigationTitle("Words")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
    }
}

/// A book's heading over its words: its cover and title, opening its page.
private struct BookWordsHeading: View {
    let book: PlayableContent

    var body: some View {
        NavigationLink(value: RouterDestination.audiobookDetail(content: book)) {
            HStack(spacing: 10) {
                ContentArtworkView(content: book, showMusicSource: false, preferredSize: 80, cornerRadius: 4)
                    .frame(width: 28, height: 28)
                Text(book.title)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the book")
    }
}

/// A word, and how long ago it was looked up.
private struct BookWordRow: View {
    let lookup: BookWordLookups.Lookup
    let book: PlayableContent

    var body: some View {
        LookUpButton(term: lookup.term) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                BookWordLabel(lookup: lookup)
                Spacer(minLength: 8)
                Text(lookup.date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            BookWordMenuItems(lookup: lookup, book: book)
        }
    }
}
