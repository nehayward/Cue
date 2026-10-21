import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// A book's long-press menu: Resume (or Play), from the start, and
/// finished or not. A book plays from where it was left, never into the
/// queue, so there are none of the queue's positions.
struct AudiobookMenuItems: View {
    let book: PlayableContent

    var body: some View {
        let progress = AudiobookProgressStore.shared.progress(for: book)
        Button {
            Task { await AudiobookPlayer.shared.play(book) }
        } label: {
            if progress?.isStarted == true {
                Label("Resume", systemImage: "play.fill")
            } else {
                Label("Play", systemImage: "play.fill")
            }
        }
        if progress?.isStarted == true || progress?.isFinished == true {
            Button {
                Task { await AudiobookPlayer.shared.play(book, from: 0) }
            } label: {
                Label("Play from Start", systemImage: "backward.end.fill")
            }
        }
        NavigationLink(value: RouterDestination.audiobookDetail(content: book)) {
            Label("View Book", systemImage: "book")
        }
        Section {
            AudiobookDownloadMenuItems(book: book)
        }
    }
}
