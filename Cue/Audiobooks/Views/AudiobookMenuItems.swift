import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// A book's long-press menu: Resume (or Play), from the start, and
/// finished or not, then the book on this device and on the Apple Watch.
/// A book plays from where it was left, never into the queue, so there are
/// none of the queue's positions.
struct AudiobookMenuItems: View {
    let book: PlayableContent

    var body: some View {
        let progress = AudiobookProgressStore.shared.progress(for: book)
        let player = AudiobookPlayer.shared
        // The book in the player already: its own play and pause.
        let isLoaded = player.isLoaded(book)
        let isPlaying = isLoaded && PlaybackRoute.shared.presented.isPlaying
        Button {
            if isLoaded {
                Task { await PlaybackRoute.shared.presented.togglePlayback() }
            } else {
                Task { await player.play(book) }
            }
        } label: {
            if isPlaying {
                Label("Pause", systemImage: "pause.fill")
            } else if progress?.isStarted == true {
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
            Label(book.isPodcastEpisode ? "View Episode" : "View Book", systemImage: book.isPodcastEpisode ? "mic" : "book")
        }
        if let podcastID = book.podcastID {
            NavigationLink(value: RouterDestination.audiobookshelfPodcast(AudiobookshelfPodcast(id: podcastID, title: book.subtitle))) {
                Label("View Podcast", systemImage: "square.stack")
            }
        }
        // Out of Continue Listening until it's listened to again.
        if ContinueListeningRemovals.shared.isListed(book) {
            Button {
                HapticManager.shared.fireHaptic(.selection)
                ContinueListeningRemovals.shared.remove(book)
            } label: {
                Label("Remove from Continue Listening", systemImage: "minus.circle")
            }
        }
        Section {
            AudiobookDownloadMenuItems(book: book)
            WatchMenuSection(item: book)
        }
    }
}
