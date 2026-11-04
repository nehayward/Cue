#if targetEnvironment(macCatalyst)
import Foundation
import Nuke
import Observation
import OSLog
import SonosKit
import UIKit

/// Cue Mini's line to the player: sends what `PlaybackRoute.presented`
/// shows (`CueMiniNowPlaying`) whenever it changes, as distributed
/// notifications through MacGlue, and runs the commands Mini sends back on
/// the same controller the player's buttons use. Mini is then Cue's player
/// in the menu bar, on this Mac or a Sonos group alike, rather than a
/// speaker remote of its own.
///
/// It follows the player with `withObservationTracking`, re-armed after
/// each change, so nothing runs while nothing changes: the clock goes over
/// as a reading and the time it was taken, and Mini runs it on. A change
/// that leaves the state as it was (a clock reading within a second of
/// where the last one sent would have run to) isn't sent, and nothing is sent
/// with no Mini running: a distributed notification goes through a system-wide
/// server, and any app on the Mac can read what's playing from one. Mini asks
/// as it launches. Nothing here touches `UserDefaults`.
///
/// `start()` once, from the window's `onAppear`.
@MainActor
final class CueMiniLink {
    static let shared = CueMiniLink()

    /// `log stream --predicate 'subsystem == "dance.cue" AND category == "cuemini"'`
    private static let log = Logger(subsystem: "dance.cue", category: "cuemini")

    /// The cover's size in points, three pixels to the point
    /// (`ContentArtworkView.maxPixelSize`): Mini draws it at 56.
    private static let coverPoints: Double = 40
    /// A burst of changes (a skip: the song, its cover, its duration, the
    /// clock) goes out as one.
    private static let coalescing: Duration = .milliseconds(120)

    private var isStarted = false
    private var sent: CueMiniNowPlaying?
    private var pendingSend: Task<Void, Never>?
    /// A send after each command, whatever the player says: a command that
    /// changed nothing observable (a speaker that didn't answer) still sets
    /// Mini's optimistic state straight.
    private var backstop: Task<Void, Never>?
    /// The cover of the item on show: its key, and the JPEG once made.
    private var cover: (key: String, jpeg: Data?)?
    private var coverTask: Task<Void, Never>?

    private var bridge: MacBridgeable? { MenuAppLaunchAtLoginManager.shared.bridge }

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true
        bridge?.observeDistributedNotification(named: CueMiniCommand.notificationName) { object in
            guard let command = CueMiniCommand(notificationObject: object) else { return }
            Task { @MainActor in
                await CueMiniLink.shared.perform(command)
            }
        }
        track()
        send(force: true, withCover: true)
    }

    // MARK: - Following the player

    /// Reads everything the state is made of under observation, and comes
    /// back on the first change to any of it.
    private func track() {
        withObservationTracking {
            _ = snapshot()
        } onChange: {
            Task { @MainActor in
                CueMiniLink.shared.changed()
            }
        }
    }

    private func changed() {
        track()
        guard pendingSend == nil else { return }
        pendingSend = Task {
            try? await Task.sleep(for: Self.coalescing)
            pendingSend = nil
            send(force: false)
        }
    }

    /// The state as the player shows it now.
    private func snapshot() -> CueMiniNowPlaying {
        let route = PlaybackRoute.shared
        let controller = route.presented
        let books = AudiobookPlayer.shared
        let display = controller.nowPlayingDisplay
        // As the mini player: not while a hand-off holds the row.
        let isBook = display != nil && books.isPlayingBook(on: controller) && !route.isHolding
        let group = controller.group

        var item: CueMiniNowPlaying.Item?
        if let display {
            var title = display.title
            var subtitle = display.subtitle
            if isBook, let book = books.current?.book {
                // The chapter over the book, as Apple Books and the watch
                // have it; the book over its author without chapters.
                if books.hasChapters, let chapter = books.currentChapter {
                    title = chapter.title
                    subtitle = book.title
                } else {
                    title = book.title
                    subtitle = book.subtitle
                }
            }
            item = .init(id: display.id, title: title, subtitle: subtitle, artworkKey: coverSource?.key, isBook: isBook)
        }

        let now = Date.now
        let span = isBook ? books.chapterSpan(on: controller) : nil
        let spanStart = span?.lowerBound ?? 0
        let duration = span.map { $0.upperBound - $0.lowerBound } ?? controller.duration
        // A book plays at its own speed on this Mac; a speaker has only 1×.
        let rate = isBook && group == nil ? books.rate : 1
        let clock = CueMiniNowPlaying.Clock(
            duration: max(duration, 0),
            position: max(controller.position(at: now) - spanStart, 0),
            readAt: now,
            isRunning: controller.isClockRunning,
            rate: rate,
            spanStart: spanStart
        )

        let movingTo = route.isHolding ? (route.group?.nameWithCount ?? "This Mac") : nil
        let place = CueMiniNowPlaying.Route(
            name: group?.nameWithCount ?? "This Mac",
            groupID: group?.coordinatorID,
            roomCount: group?.rooms.count ?? 0,
            movingTo: movingTo
        )

        let transport = CueMiniNowPlaying.Transport(
            showsPrevious: controller.showsPrevious,
            canGoBack: controller.canGoBack,
            showsNext: controller.showsNext,
            hasNext: controller.hasNext,
            canScrub: controller.canScrub && duration > 0,
            skipBack: isBook ? AudiobookPlayer.skipBackInterval : nil,
            skipForward: isBook ? AudiobookPlayer.skipForwardInterval : nil,
            showsPlayModes: display != nil && !isBook && controller.duration > 0
        )

        return CueMiniNowPlaying(
            processID: ProcessInfo.processInfo.processIdentifier,
            sentAt: now,
            item: item,
            clock: clock,
            isPlaying: controller.isPlaying,
            isActive: controller.isActive,
            isLoading: controller.isLoading,
            route: place,
            transport: transport,
            isShuffled: controller.isShuffled,
            repeatMode: CueMiniNowPlaying.RepeatMode(rawValue: controller.repeatMode.rawValue) ?? .off,
            sonosEnabled: SonosService.shared.isEnabled
        )
    }

    /// Sends the state, unless it's the state last sent: `force` sends it
    /// anyway, with a fresh clock reading, and `withCover` the cover made
    /// for it again too (for a Mini that's just launched).
    private func send(force: Bool, withCover: Bool = false) {
        guard bridge?.isCueMiniRunning == true else { return }
        let state = snapshot()
        updateCover(resending: withCover)
        if !force, let sent, sent.isSame(as: state) { return }
        guard let object = state.notificationObject else { return }
        if sent?.item?.id != state.item?.id || sent?.isPlaying != state.isPlaying {
            Self.log.info("sent \(state.item?.title ?? "nothing", privacy: .public), \(state.isPlaying ? "playing" : "paused", privacy: .public) on \(state.route.name, privacy: .public)")
        }
        sent = state
        bridge?.postDistributedNotification(named: CueMiniNowPlaying.changedNotification, object: object)
    }

    // MARK: - The cover

    /// What the cover is drawn from and its key: a book's own cover for
    /// any of its files, else the item on show. Nil for one without.
    private var coverSource: (content: PlayableContent, url: URL, key: String)? {
        let controller = PlaybackRoute.shared.presented
        let books = AudiobookPlayer.shared
        var content = controller.nowPlayingDisplay
        if books.isPlayingBook(on: controller), let book = books.current?.book, (book.artwork ?? book.thumbnail) != nil {
            content = book
        }
        guard let content, let url = content.artwork ?? content.thumbnail else { return nil }
        return (content, url, Self.stableHash("\(content.imageKey)|\(url.absoluteString)"))
    }

    /// Makes the cover of the item on show when it's a new one, and sends
    /// it once it's made; `resending` sends the one made again.
    private func updateCover(resending: Bool) {
        guard let source = coverSource else {
            coverTask?.cancel()
            cover = nil
            return
        }
        if let cover, cover.key == source.key {
            if resending, let jpeg = cover.jpeg {
                sendCover(key: source.key, jpeg: jpeg)
            }
            return
        }
        cover = (source.key, nil)
        coverTask?.cancel()
        let request = ContentArtworkView.artworkRequest(for: source.content, url: source.url, preferredSize: Self.coverPoints)
        coverTask = Task {
            let image = try? await ImagePipeline.shared.image(for: request)
            let jpeg = await Task.detached(priority: .utility) {
                image?.jpegData(compressionQuality: 0.75)
            }.value
            guard !Task.isCancelled, cover?.key == source.key else { return }
            guard let jpeg else {
                Self.log.info("no cover for \(source.content.title, privacy: .public)")
                return
            }
            cover = (source.key, jpeg)
            sendCover(key: source.key, jpeg: jpeg)
        }
    }

    private func sendCover(key: String, jpeg: Data) {
        guard let object = CueMiniCover(key: key, jpeg: jpeg).notificationObject else { return }
        bridge?.postDistributedNotification(named: CueMiniCover.notificationName, object: object)
    }

    /// FNV-1a: a short key that's the same on every launch (`hashValue`
    /// isn't).
    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    // MARK: - Commands

    /// Runs `command` on what the player shows, as its own buttons do
    /// (`MusicPlaybackView.transportButtons`).
    private func perform(_ command: CueMiniCommand) async {
        let controller = PlaybackRoute.shared.presented
        switch command {
        case .togglePlayback:
            await PlayerCommands.togglePlayback()
        case .next:
            await PlayerCommands.next()
        case .previous:
            await PlayerCommands.previous()
        case .skip(let seconds):
            guard AudiobookPlayer.shared.isPlayingBook(on: controller) else { return }
            await AudiobookPlayer.shared.skip(by: seconds)
        case .seek(let seconds, let itemID):
            guard controller.nowPlayingDisplay?.id == itemID, controller.canScrub else { return }
            await controller.seek(to: max(seconds, 0))
        case .setShuffle(let on):
            await controller.setShuffle(on)
        case .setRepeat(let mode):
            guard let mode = LocalPlaybackService.RepeatMode(rawValue: mode.rawValue) else { return }
            await controller.setRepeatMode(mode)
        case .refresh:
            send(force: true, withCover: true)
            return
        }
        Self.log.info("ran \(String(describing: command), privacy: .public)")
        backstop?.cancel()
        backstop = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            send(force: true)
        }
    }
}

private extension CueMiniNowPlaying {
    /// How far a clock reading can be from where the last one sent would
    /// have run to before it's sent: a correction, not drift.
    static let clockTolerance: TimeInterval = 1

    /// The same as `other` as Mini would draw it: equal but for when each
    /// was read, with clocks that agree to within `clockTolerance`.
    func isSame(as other: CueMiniNowPlaying) -> Bool {
        let now = Date.now
        guard abs(clock.position(at: now) - other.clock.position(at: now)) < Self.clockTolerance else { return false }
        var mine = self
        mine.sentAt = other.sentAt
        mine.clock.readAt = other.clock.readAt
        mine.clock.position = other.clock.position
        return mine == other
    }
}
#endif
