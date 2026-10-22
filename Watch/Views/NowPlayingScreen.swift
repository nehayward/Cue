import SwiftUI
import WatchKit

/// Now Playing: the system's own player, where the Digital Crown sets the
/// volume and the route picker is a tap away, driven by `WatchPlayer`'s
/// commands — a book's skips back 15 s and ahead 30 s, its chapter and the
/// time into it. While a book plays, the top right opens its page: its
/// chapters to jump to, its speed, and Play from Start.
struct NowPlayingScreen: View {
    @Environment(WatchPlayer.self) private var player
    @Environment(\.zoomNamespace) private var zoom

    var body: some View {
        NowPlayingView()
            .toolbar {
                if let book = player.book {
                    ToolbarItem(placement: .topBarTrailing) {
                        let route = BookRoute(key: book.key)
                        NavigationLink(value: route) {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("Chapters and Speed")
                        .zoomSource(route, in: zoom)
                    }
                }
            }
    }
}
