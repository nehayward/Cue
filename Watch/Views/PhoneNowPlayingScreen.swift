import SwiftUI
import WatchKit
import WatchSync

/// Now Playing for what the iPhone plays (`PhoneNowPlaying`), opened from
/// the home screen's iPhone card: the same face as the watch's own player
/// (`PlayerFace`), filling the screen — the song and its artist, or a book's
/// chapter and the book, a thin line of how far in with the time left, and
/// Previous, Play and Next, each press carried out by the iPhone's own
/// player, here or on its Sonos group (a book's skip back 15 s and ahead
/// 30 s, as there). Top right, a book's chapters (`PhoneChaptersScreen`) or
/// music's Up Next (`PhoneQueueScreen`); along the bottom, the sleep timer
/// and a book's speed, where it plays — a tap opens Play On, which moves it
/// to another of the iPhone's routes, or a book on the watch to the watch —
/// and the iPhone's volume on the Digital Crown.
///
/// Not the system's `NowPlayingView`, which picks its source itself: with
/// a book loaded on the watch it showed the watch's book, whatever the card
/// said.
struct PhoneNowPlayingScreen: View {
    @Environment(PhoneNowPlaying.self) private var phone
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchPlayer.self) private var player
    @Environment(\.zoomNamespace) private var zoom
    @Environment(\.showPlayer) private var showPlayer
    @State private var isShowingOptions = false
    @State private var isChoosingPlace = false

    /// The speeds the iPhone's player offers a book.
    private static let rateChoices: [Double] = [0.75, 1, 1.1, 1.2, 1.3, 1.5, 1.75, 2, 2.5, 3]

    var body: some View {
        VStack {
            if let playing = phone.current {
                face(playing)
            } else {
                notPlaying
            }
        }
        .containerBackground(for: .navigation) {
            ImageMeshFill(image: phone.artwork)
        }
        .toolbar {
            if let playing = phone.current {
                ToolbarItem(placement: .topBarTrailing) {
                    list(for: playing)
                }
            }
        }
        .sheet(isPresented: $isShowingOptions) {
            if let playing = phone.current {
                PlayerOptionsSheet(
                    endTitle: playing.isBook ? "End of Chapter" : "End of Song",
                    sleepsAt: playing.sleepsAt,
                    sleepsAtEnd: playing.sleepsAtEnd,
                    // Sonos plays books at 1×.
                    speed: playing.isBook && !playing.isOnSpeaker ? (playing.rate, Self.rateChoices) : nil,
                    chooseSleep: phone.setSleepTimer,
                    chooseSpeed: phone.setSpeed
                )
            }
        }
        .sheet(isPresented: $isChoosingPlace) {
            PlayOnSheet(current: phone.routes?.current.map(PlayOnChoice.phone), offersWatch: watchBook != nil) { choice in
                switch choice {
                case .watch:
                    playOnWatch()
                case let .phone(id):
                    phone.switchRoute(to: id)
                }
            }
        }
    }

    private func face(_ playing: WatchPhoneNowPlaying) -> some View {
        let clock = playing.barLength.map { duration in
            PlayerClock(elapsed: playing.elapsed(at: .now) ?? 0, duration: duration, at: .now, rate: playing.rate, isPlaying: playing.isPlaying)
        }
        return PlayerFace(
            title: playing.isBook ? playing.chapter ?? playing.title : playing.title,
            subtitle: playing.isBook && playing.chapter != nil ? playing.title : playing.artist ?? "",
            clock: clock,
            isPlaying: playing.isPlaying,
            isBook: playing.isBook,
            canGoBack: playing.canGoBack,
            hasNext: playing.hasNext,
            place: playing.isOnSpeaker ? .speaker(playing.destination) : .iPhone,
            hasSleepTimer: playing.hasSleepTimer,
            volume: .companion,
            previous: { phone.perform(.previous) },
            playPause: { phone.togglePlayPause() },
            next: { phone.perform(.next) },
            options: { isShowingOptions = true },
            choosePlace: { isChoosingPlace = true }
        ) {
            PhoneArtwork(image: phone.artwork, symbol: playing.isBook ? "book.closed" : "music.note")
        }
    }

    /// The iPhone's book, when it's on the watch and the part it's at is
    /// here: Play On offers the watch.
    private var watchBook: (pick: WatchPick, time: TimeInterval)? {
        guard let playing = phone.current, let key = playing.bookKey,
              let pick = store.picks.pick(key: key), let time = playing.bookTime(at: .now),
              player.canPlayBook(pick, from: time) else { return nil }
        return (pick, time)
    }

    /// The iPhone's book goes on here, from where the iPhone has it: the
    /// iPhone pauses, and the watch's player takes this one's place.
    private func playOnWatch() {
        guard let book = watchBook else { return }
        BookPlayback.playHere(book.pick, from: book.time)
        showPlayer?(.nowPlaying)
    }

    /// A book's chapters, or music's Up Next while it plays from a queue.
    @ViewBuilder
    private func list(for playing: WatchPhoneNowPlaying) -> some View {
        if playing.isBook, playing.chapter != nil {
            NavigationLink(value: HomeRoute.phoneChapters) {
                Image(systemName: "list.bullet")
            }
            .accessibilityLabel("Chapters")
            .zoomSource(HomeRoute.phoneChapters, in: zoom)
        } else if !playing.isBook, playing.queueCount > 0 {
            NavigationLink(value: HomeRoute.phoneQueue) {
                Image(systemName: "list.bullet")
            }
            .accessibilityLabel("Up Next")
            .zoomSource(HomeRoute.phoneQueue, in: zoom)
        }
    }

    /// Stopped on the iPhone, or the iPhone went out of reach, while open.
    private var notPlaying: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(phone.isPhoneInReach ? "Nothing playing on iPhone" : "iPhone out of reach")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
