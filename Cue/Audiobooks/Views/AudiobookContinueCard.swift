import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The tab's lead, as Audible has it: one card of the books not finished,
/// the one listened to last on top, each with its own Play. Past the first
/// few, the title opens them all.
struct AudiobookContinueCard: View {
    let books: [PlayableContent]

    @Environment(Router.self) private var router
    @State private var store = AudiobookProgressStore.shared

    private static let shownCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                router.navigate(to: allBooks)
            } label: {
                HStack {
                    Text("Continue Listening")
                    Spacer()
                    if books.count > Self.shownCount {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.title3.bold())
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(books.count <= Self.shownCount)
            .accessibilityAddTraits(.isHeader)
            .fontDesign(.rounded)
            .padding(.bottom, 6)

            if books.isEmpty {
                Text("The books you're listening to wait here, ready to pick up where you left them.")
                    .font(.callout)
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            // Rounded is set on each part rather than here: the outermost
            // `.fontDesign` wins, and the book's title is New York.
            ForEach(books.prefix(Self.shownCount)) { book in
                AudiobookContinueRow(book: book)
                    .padding(.vertical, 8)
            }
        }
        // A book played moves to the top: the rows slide into their new
        // order rather than jump.
        .animation(.smooth, value: books.prefix(Self.shownCount).map(\.id))
        .padding(16)
        .background(.fill.quaternary, in: .rect(cornerRadius: 24))
    }

    /// Every book not finished, as a list of its own, read again when one's
    /// taken out of it from its menu.
    private var allBooks: RouterDestination {
        let books = books
        let store = store
        let removals = ContinueListeningRemovals.shared
        return .playableList(title: "Continue Listening", showSectionIndex: false, changeToken: { removals.version }) { offset in
            guard offset == 0 else { return [] }
            return await MainActor.run {
                books.filter { !removals.isRemoved($0) }.map { $0.withAudiobookProgress(store.progress(for: $0)) }
            }
        }
    }
}
