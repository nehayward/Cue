import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// A book's row: the shelf's ordinary row, with how much is left under the
/// author and a thin progress line under the text. Reads only its own
/// book's progress.
struct AudiobookRow: View {
    let book: PlayableContent

    var body: some View {
        let progress = AudiobookProgressStore.shared.progress(for: book)
        let isListened = progress?.isStarted == true || progress?.isFinished == true
        PlayableContentView(item: book.withAudiobookProgress(progress), progress: isListened ? progress?.fraction : nil)
    }
}
