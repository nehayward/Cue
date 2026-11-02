import SonosKit
import SwiftUI

/// A looked-up word's menu, wherever it shows: Play from Here (the start of
/// its line, in its book), Copy, and Remove from its book's words.
struct BookWordMenuItems: View {
    let lookup: BookWordLookups.Lookup
    let book: PlayableContent
    /// The book read whole, for Undo to name the chapter it goes back to.
    var audiobook: Audiobook?
    /// After Play from Here: a sheet showing the word closes.
    var onPlay: () -> Void = {}

    var body: some View {
        Button("Play from Here", systemImage: "play") {
            onPlay()
            Task { await AudiobookPlayer.shared.pick(book, at: lookup.position, in: audiobook) }
        }
        Button("Copy", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = lookup.term
        }
        Button(role: .destructive) {
            withAnimation { BookWordLookups.shared.remove(lookup, from: book) }
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }
}
