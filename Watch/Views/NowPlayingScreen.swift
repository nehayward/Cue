import SwiftUI
import WatchKit
import WatchSync

/// Now Playing for what the watch plays (`WatchPlayer`), opened from the
/// home screen's watch card: the same face as the iPhone's player
/// (`PlayerFace`), filling the screen — the song and its artist, or a book's
/// chapter and the book, a thin line of how far in with the time left, and
/// Previous, Play and Next (a book's back 15 s and ahead 30 s). While a
/// book plays, the top right opens its page: its chapters to jump to, and
/// Play from Start. Along the bottom, the sleep timer and a book's speed,
/// the watch's glyph — a tap opens Play On, which moves it to the iPhone or
/// a speaker it plays to (a book from its place here, music as the album or
/// playlist it's from, from the song playing) — and the volume on the
/// Digital Crown.
///
/// Not the system's `NowPlayingView`, which picks its source itself: with
/// the iPhone playing too it showed the iPhone's, under the watch's card.
struct NowPlayingScreen: View {
    @Environment(WatchPlayer.self) private var player
    @Environment(WatchBookStore.self) private var books
    @Environment(WatchDownloadStore.self) private var store
    @Environment(PhoneNowPlaying.self) private var phone
    @Environment(\.zoomNamespace) private var zoom
    @Environment(\.showPlayer) private var showPlayer
    @State private var isShowingOptions = false
    @State private var isChoosingPlace = false

    private var artworkURL: URL? {
        player.book?.artworkURL ?? player.current?.artworkURL
    }

    var body: some View {
        VStack {
            if player.current != nil {
                face
            } else {
                Text("Nothing playing")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .navigation) {
            CoverMeshFill(url: artworkURL)
        }
        .toolbar {
            if let book = player.book {
                ToolbarItem(placement: .topBarTrailing) {
                    let route = BookRoute(key: book.key)
                    NavigationLink(value: route) {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("Chapters")
                    .zoomSource(route, in: zoom)
                }
            }
        }
        .sheet(isPresented: $isShowingOptions) {
            options
        }
        .sheet(isPresented: $isChoosingPlace) {
            PlayOnSheet(current: .watch, offersWatch: true) { choice in
                if case let .phone(id) = choice {
                    playOnPhone(WatchPhoneTarget(routeID: id))
                }
            }
        }
    }

    /// What plays here goes on there: a book from its place here, music as
    /// the album or playlist the song playing is from, from that song (the
    /// song alone, added by itself). The watch pauses, and the iPhone's
    /// player takes this one's place.
    private func playOnPhone(_ target: WatchPhoneTarget) {
        if let book = player.book {
            BookPlayback.playOnPhone(book, from: nil, on: target)
        } else if let song = player.current {
            let key = store.songsByPick.first { $0.value.contains { $0.key == song.key } }?.key
            let pick = key.flatMap { store.picks.pick(key: $0) } ?? song.pick
            player.pause()
            phone.playItem(pick, from: song.contentID, on: target)
        }
        showPlayer?(.phoneNowPlaying)
    }

    private var face: some View {
        let progress = player.progress
        let clock = progress.map {
            PlayerClock(elapsed: $0.elapsed, duration: $0.duration, at: .now, rate: player.rate, isPlaying: player.isPlaying)
        }
        let book = player.book
        return PlayerFace(
            title: book == nil ? player.current?.title ?? "" : progress?.chapter?.title ?? book?.title ?? "",
            subtitle: book.map { progress?.chapter == nil ? $0.subtitle : $0.title } ?? player.current?.artist ?? "",
            clock: clock,
            isPlaying: player.isPlaying,
            isBook: book != nil,
            canGoBack: true,
            hasNext: book != nil || player.index + 1 < player.queue.count,
            place: .watch,
            hasSleepTimer: player.sleepTimer != nil,
            volume: .local,
            previous: {
                if book == nil {
                    player.previous()
                } else {
                    player.skip(by: -WatchPlayer.skipBack)
                }
            },
            playPause: { player.togglePlayPause() },
            next: {
                if book == nil {
                    player.next()
                } else {
                    player.skip(by: WatchPlayer.skipAhead)
                }
            },
            options: { isShowingOptions = true },
            choosePlace: { isChoosingPlace = true }
        ) {
            ArtworkView(url: artworkURL, symbol: book == nil ? "music.note" : "book.closed")
        }
    }

    private var options: some View {
        let book = player.book
        let sleepsAt: Date? = if case let .at(date) = player.sleepTimer { date } else { nil }
        return PlayerOptionsSheet(
            endTitle: book == nil ? "End of Song" : "End of Chapter",
            sleepsAt: sleepsAt,
            sleepsAtEnd: player.sleepTimer == .endOfChapter,
            speed: book.map { (books.rate(for: $0.key), WatchBookStore.rateChoices) },
            chooseSleep: { player.setSleepTimer(WatchPlayer.SleepTimer($0)) },
            chooseSpeed: { rate in
                if let book {
                    player.setRate(rate, for: book)
                }
            }
        )
    }
}
