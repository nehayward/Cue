import Foundation
import WatchSync
import WidgetKit

/// Keeps the widgets' copy of the watch's state (`WatchWidgetState`, in the
/// app group) current, and asks WidgetKit to reload when it changes: a few
/// seconds after the last change, so an album landing song by song is one
/// reload, not dozens.
@MainActor
enum WidgetStatePublisher {
    private static var pending: Task<Void, Never>?
    private static var published: WatchWidgetState?

    static func schedule() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            publish()
        }
    }

    private static func publish() {
        let store = WatchDownloadStore.shared
        let player = WatchPlayer.shared
        let state = WatchWidgetState(
            songsOnWatch: store.downloadedCount,
            songsToDownload: store.remainingCount,
            bytesUsed: store.bytesUsed,
            nowPlayingTitle: player.current?.title,
            nowPlayingArtist: player.current?.artist,
            isPlaying: player.isPlaying
        )
        guard state != published else { return }
        published = state
        state.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
