import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// `MusicLeftOffCard` as a section of its own, at the top of a music
/// library: apart from the library's rows, so it doesn't cut into their
/// group, and only while it has something to show, so it leaves no gap.
struct MusicLeftOffSection: View {
    @State private var player = AudiobookPlayer.shared

    var body: some View {
        if player.musicSetAside != nil {
            Section {
                MusicLeftOffCard()
            }
        }
    }
}
