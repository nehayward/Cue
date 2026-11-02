import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The way between a book and the music it was started over, for the
/// player's menu: Back to Music while a book plays on this device with a
/// music queue set aside, and Back to Book while music plays after a book
/// was left for it.
struct BookMusicSwitchMenuItems: View {
    let isBook: Bool

    @State private var player = AudiobookPlayer.shared

    var body: some View {
        if isBook, let aside = player.musicSetAside {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                Task { try? await player.returnToMusic() }
            } label: {
                Label("Back to Music", systemImage: "music.note.list")
                Text(aside.title)
            }
        } else if !isBook, let book = player.bookToReturnTo {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                Task { await player.play(book) }
            } label: {
                Label("Back to Book", systemImage: "book")
                Text(book.title)
            }
        }
    }
}
