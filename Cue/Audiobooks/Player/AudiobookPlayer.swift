import Foundation
import MusicSearchKit
import Observation
import OSLog
import SonosKit
import UIKit

/// Plays books: from where the listener left them, as their files, on this
/// device or a speaker, and keeps their place.
///
/// A book doesn't go through the music queue's positions (Play Next, Play
/// Last): playing one replaces the queue with its files, starting at the
/// file and offset its place maps to, and the place is kept for the book
/// itself rather than the queue — so music played in between doesn't lose
/// it. The player surfaces ask `isPlayingBook(on:)` to swap Previous and
/// Next for skips, and offer speed and chapters.
///
/// It follows whatever the route presents (`PlaybackRoute.presented`)
/// every couple of seconds while a book is loaded, on the device and on a
/// speaker alike: that reading is where the book is, and is saved here
/// (`AudiobookProgressStore`) and on the book's server.
@MainActor
@Observable
final class AudiobookPlayer {
    static let shared = AudiobookPlayer()

    static let log = Logger(subsystem: "dance.cue", category: "audiobooks")

    /// The book loaded to play, on the device or a speaker. Nil once
    /// something else has taken over.
    private(set) var current: Audiobook?
    /// Book time, as last read from the player.
    private(set) var position: TimeInterval = 0 {
        didSet { updateChapter() }
    }

    /// The chapter playing, from the last reading. Kept apart from
    /// `position`, which moves every couple of seconds: what shows only the
    /// chapter (a menu, the chapter line) changes only when the chapter
    /// does, and an open menu isn't rebuilt under the finger.
    private(set) var currentChapter: AudiobookChapter?

    private func updateChapter() {
        let chapter = current?.chapter(at: position)
        if chapter != currentChapter {
            currentChapter = chapter
        }
    }
    /// A book is being read from its server to play.
    private(set) var isLoading = false

    /// How fast the loaded book plays on this device, 1 being normal. Each
    /// book keeps its own (`bookRates`), so speeding one up leaves the rest
    /// as they were, and a book never changed plays at 1×. Speakers play at
    /// 1× whatever this says: Sonos has no other speed.
    private(set) var rate: Double = 1

    static let rates: [Double] = [0.75, 1, 1.1, 1.2, 1.3, 1.5, 1.75, 2, 2.5, 3]
    static let skipBackInterval: TimeInterval = 15
    static let skipForwardInterval: TimeInterval = 30

    @ObservationIgnored private var monitor: Task<Void, Never>?
    /// Readings of something else playing, in a row. A few mean the book
    /// was left.
    @ObservationIgnored private var misses = 0
    /// Until then a reading of something else is the player still loading
    /// the book, not the book left.
    @ObservationIgnored private var graceUntil: Date = .distantPast
    @ObservationIgnored private var lastServerSync: Date = .distantPast
    @ObservationIgnored private var lastServerPosition: TimeInterval?
    @ObservationIgnored private var wasPlaying = false
    @ObservationIgnored private var lastStoredPosition: TimeInterval?
    /// The last reading of the book playing, when it's newer than the one
    /// kept (they're kept every `storeInterval`): kept when the book is
    /// left or the app goes to the background, so nothing heard is lost.
    @ObservationIgnored private var unrecorded: AudiobookProgress?
    /// Where `start` or `jump` sent the player, until a reading shows it got
    /// there. Until then a reading at the top of the file is the file still
    /// loading (the seek lands once it can play), not the listener's place.
    @ObservationIgnored private var arriving: TimeInterval? {
        didSet {
            if let arriving, arriving != oldValue {
                arrivingSince = .now
                leaving = nil
            }
        }
    }
    /// When the player was last sent to `arriving`.
    @ObservationIgnored private var arrivingSince: Date = .distantPast
    /// Where the player was when `jump` sent it to `arriving`, as it read
    /// then: a reading there just after is the seek not landed yet.
    @ObservationIgnored private var leaving: TimeInterval?
    /// The `arriving` a held-back reading was last logged for, so a trip is
    /// logged once.
    @ObservationIgnored private var heldBackOnWayTo: TimeInterval?
    /// The file and the offset into it of the last reading taken, to log
    /// the queue going on to another file.
    @ObservationIgnored private var lastPart: Int?
    @ObservationIgnored private var lastOffset: TimeInterval = 0
    /// The last reading of the book's place, when it was taken, and whether
    /// it was playing: a reading far from where listening since would have
    /// got to is a move, and where it moved from goes in the place history.
    @ObservationIgnored private var lastReading: (time: TimeInterval, at: Date, playing: Bool)?
    /// How far a move goes before the place it left is worth going back to:
    /// past a skip, short of a chapter.
    static let placeJump: TimeInterval = 60
    /// The book was heard to its end, and nothing has played since.
    @ObservationIgnored private var reachedEnd = false
    /// The server has been told the book is finished.
    @ObservationIgnored private var finishReported = false
    /// A mark set the book's place (Mark as Finished, Mark as Unfinished):
    /// no reading is kept until it plays again (`noteMarked`).
    @ObservationIgnored private var holdsReadings = false
    @ObservationIgnored private var backgroundObserver: (any NSObjectProtocol)?

    /// Each book's speed, by `AudiobookProgressStore.key`; a book at 1× has
    /// none.
    private static let ratesKey = "dance.cue.audiobookRates"
    private static let serverSyncInterval: TimeInterval = 15
    private static let storeInterval: TimeInterval = 10
    /// How near the top of a file a reading still counts as the file
    /// loading, and how near where it was sent as having got there.
    private static let arrivalTolerance: TimeInterval = 3
    /// How long after the player is sent somewhere a reading far from there
    /// is taken as it not having got there yet.
    private static let arrivalGrace: TimeInterval = 5

    private init() {
        SonosService.shared.beforePlay = { ip in
            await AudiobookPlayer.shared.smartResumeOnSpeaker(ip: ip)
        }
        leftBook = UserDefaults.standard.data(forKey: Self.leftBookKey).flatMap { try? JSONDecoder().decode(LeftBook.self, from: $0) }
        current = Self.loadCurrent()
        updateChapter()
        rate = Self.rate(for: current?.book)
        if let current {
            graceUntil = .now.addingTimeInterval(30)
            startMonitoring()
            // The session its files stream through may have ended while
            // Cue was closed (they last a day and a half unheard); one is
            // open again before Play is pressed.
            let itemID = current.book.content.id
            if current.book.content.service == .audiobookshelf, !AudiobookshelfAPI.hasOpenSession(for: itemID) {
                Task { _ = await AudiobookshelfAPI.shared.startSession(itemID: itemID) }
            }
        }
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flush()
            }
        }
    }

    // MARK: - Asking

    /// Whether `controller` is playing one of the loaded book's files.
    func isPlayingBook(on controller: any PlaybackController) -> Bool {
        current?.partIndex(of: controller.nowPlayingDisplay) != nil
    }

    /// Whether `book` is the book loaded and what the player is on, playing
    /// or paused: its Play is then the player's own play and pause, not a
    /// start from its kept place, which lags what's heard by a few seconds.
    func isLoaded(_ book: PlayableContent) -> Bool {
        current?.book.isSameBook(as: book) == true && isPlayingBook(on: PlaybackRoute.shared.presented)
    }

    /// Whether `item` is one of the loaded book's files.
    func contains(_ item: PlayableContent?) -> Bool {
        current?.partIndex(of: item) != nil
    }

    /// The book `content` is, or is one of the files of: itself for a book,
    /// the loaded book or the one last left for one of their files. Nil for
    /// anything else. For pages opened from a book's file (the player's
    /// title and artist lines), which are then the book's and its author's.
    func book(containing content: PlayableContent) -> PlayableContent? {
        if content.content.type == .audiobook { return content }
        if let current, current.partIndex(of: content) != nil { return current.book }
        if let leftBook, leftBook.partIDs.contains(content.id) { return leftBook.book }
        return nil
    }

    /// The rate this device plays `item` at: the book speed for a book's
    /// file, normal for anything else.
    func playbackRate(for item: PlayableContent?) -> Float {
        contains(item) ? Float(rate) : 1
    }

    /// What's left to hear, as "33m left in chapter" — or of the whole book
    /// ("5h 3m left in book") with `ofBook`, or when it has no chapters but
    /// itself — at the speed it plays at: the book's on this device, 1× on
    /// a speaker. `compact` leaves out "in chapter" and "in book", for a
    /// narrow line. Nil with no book loaded.
    func timeLeftText(ofBook: Bool = false, compact: Bool = false) -> String? {
        guard let current else { return nil }
        let speed = PlaybackRoute.shared.controller.group == nil ? rate : 1
        if !ofBook, hasChapters, let chapter = currentChapter {
            let left = "\(AudiobookFormat.duration(max(chapter.end - position, 0) / speed)) left"
            return compact ? left : "\(left) in chapter"
        }
        let left = "\(AudiobookFormat.duration(max(current.duration - position, 0) / speed)) left"
        return compact || !hasChapters ? left : "\(left) in book"
    }

    /// Whether the loaded book has chapters other than itself, so its time
    /// left can be the chapter's as well as the book's.
    var hasChapters: Bool {
        (current?.chapters.count ?? 0) > 1
    }

    // MARK: - Playing

    /// Where a book plays.
    enum Target {
        /// Where the route goes: this device, or the chosen speaker.
        case route
        case device
        /// A speaker it was dropped on.
        case group(GroupRoom)
    }

    /// Plays `book` from `time` (book time), or from where it was left.
    func play(_ book: PlayableContent, from time: TimeInterval? = nil, on target: Target = .route) async {
        forgetFailures()
        isLoading = true
        defer { isLoading = false }
        // Read again even when it's the book already loaded: another player
        // may have moved its place on the server since. Offline, the copy
        // held will do.
        let audiobook: Audiobook
        if let loaded = await AudiobookLibrary.load(book) {
            audiobook = loaded
        } else if let current, current.book.id == book.id, current.book.content.service == book.content.service {
            audiobook = current
        } else {
            AlertService.shared.showAlert(with: "Couldn't open “\(book.title)”", imageName: "exclamationmark.triangle")
            return
        }
        let reading = AudiobookLibrary.progress(for: audiobook)
        let resumeFrom: TimeInterval
        if let time {
            resumeFrom = time
        } else if let reading, reading.isStarted {
            resumeFrom = await resumeTime(for: audiobook, from: reading.position, afterPausing: Date.now.timeIntervalSince(reading.updatedAt))
        } else {
            resumeFrom = 0
        }
        let startTime = min(max(resumeFrom, 0), audiobook.duration)
        let local = AudiobookProgressStore.shared.progress(for: audiobook.book)
        let from = time != nil ? "asked" : reading == nil ? "the top" : reading == local ? "this device's place" : "the server's place"
        Self.log.notice("play \(audiobook.book.title, privacy: .public) at \(Int(startTime)) s (\(audiobook.chapter(at: startTime)?.title ?? "-", privacy: .public)), from \(from, privacy: .public); this device \(local.map { "\(Int($0.position)) s" } ?? "none", privacy: .public), server \(audiobook.serverProgress.map { "\(Int($0.position)) s" } ?? "none", privacy: .public)")
        if let local, reading == local, let server = audiobook.serverProgress, AudiobookProgress.preferring(local: local, server: server) == server {
            Self.log.notice("kept this device's place over the server's newer \(Int(server.position)) s, which says only that a file was played")
        }
        // This device's place, kept before a play that goes elsewhere: From
        // Start, a chapter picked on the book's page, or another player's
        // place taken over this one's.
        let places = AudiobookPlaceHistory.shared
        if let local, !local.isFinished, local.position > 0, abs(local.position - startTime) > Self.placeJump {
            if time != nil {
                places.record(.jumpedFrom, at: local.position, to: startTime, for: audiobook.book)
            } else {
                places.record(.replaced, at: local.position, to: startTime, for: audiobook.book, from: AudiobookPlaceHistory.Place.Source(server: audiobook.book.content.service))
            }
        }
        // The book, not its files: Recently Played opens its page. Only
        // once it's playing: one that wouldn't start wasn't listened to.
        if await start(audiobook, at: startTime, on: target) {
            PlayHistoryService.shared.record(audiobook.book)
            places.record(.started, at: startTime, for: audiobook.book)
        }
    }

    /// Moves to `time` in the loaded book: a seek within the file playing,
    /// else the file it falls in, from there.
    func jump(to time: TimeInterval) async {
        guard let current else { return }
        forgetFailures()
        let target = min(max(time, 0), current.duration)
        let location = current.timeline.location(at: target)
        let controller = PlaybackRoute.shared.controller
        // Where it was, to go back to. The readings after aren't measured
        // against it: this move is already noted.
        let from = readPosition(on: controller) ?? position
        if abs(from - target) > Self.placeJump {
            AudiobookPlaceHistory.shared.record(.jumpedFrom, at: from, to: target, for: current.book)
        }
        lastReading = nil
        // A move the listener made, not the queue running out at the end.
        reachedEnd = false
        position = target
        let wasAt = current.partIndex(of: controller.nowPlayingDisplay).map {
            current.time(part: $0, offset: controller.position())
        }
        arriving = target
        leaving = wasAt
        // A move the listener made: kept now, even if nothing plays after it.
        record(AudiobookProgress(position: target, duration: current.duration), of: current)
        if current.partIndex(of: controller.nowPlayingDisplay) == location.part {
            await controller.seek(to: location.offset)
            return
        }
        if controller.group == nil {
            let local = LocalPlaybackService.shared
            if let index = local.queue.firstIndex(where: { current.partIndex(of: $0) == location.part }) {
                do {
                    try await local.resume(at: index, from: location.offset)
                    return
                } catch {
                    Self.log.error("jump: resume at \(index) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        await start(current, at: target)
    }

    /// Plays the loaded book on this device from its kept place, for Play
    /// on a queue that holds its files with nothing armed: the queue as the
    /// app left it at launch, or one whose file wouldn't load. The queue's
    /// own spot is only as good as its last save (a file still loading
    /// reads as its top), and the book may have been moved since on
    /// another player.
    ///
    /// `queueSpot` is the queue's own spot in the file it's on: where Play
    /// goes back a little from (`SmartResume`) when it's the book's place
    /// too, as a pause leaves it.
    func resumeOnDevice(from queueSpot: TimeInterval) async {
        guard let current else { return }
        forgetFailures()
        await prepareConnection(for: current)
        let local = LocalPlaybackService.shared
        let kept = AudiobookProgressStore.shared.progress(for: current.book)
        let queueTime = current.partIndex(of: local.nowPlaying).map { current.time(part: $0, offset: queueSpot) }
        let time: TimeInterval
        if let arriving {
            // A place just picked, or where a file stopped: exactly there.
            time = arriving
        } else if let queueTime, kept.map({ abs($0.position - queueTime) <= Self.storeInterval + 1 }) ?? true {
            // A little back from it, as from a pause (`SmartResume`).
            if let kept {
                time = await resumeTime(for: current, from: queueTime, afterPausing: Date.now.timeIntervalSince(kept.updatedAt))
            } else {
                time = queueTime
            }
        } else if let kept, kept.isStarted {
            // Moved since the queue's spot was saved.
            time = await resumeTime(for: current, from: kept.position, afterPausing: Date.now.timeIntervalSince(kept.updatedAt))
        } else {
            time = kept?.resumePosition ?? position
        }
        let location = current.timeline.location(at: time)
        guard let index = local.queue.firstIndex(where: { current.partIndex(of: $0) == location.part }) else {
            await start(current, at: time, on: .device)
            return
        }
        Self.log.notice("resume \(current.book.title, privacy: .public) at \(Int(time)) s (\(current.chapter(at: time)?.title ?? "-", privacy: .public))")
        position = time
        arriving = time
        do {
            try await local.resume(at: index, from: location.offset)
        } catch {
            Self.log.error("resume at \(index) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Smart Resume on this device: where in `item`, one of the loaded
    /// book's files, paused at `offset` since `pausedAt`, Play goes back to
    /// (`SmartResume`), in a pause in the speech `heard` up to there (the
    /// file's audio, on its clock) when there's one near, and held to the
    /// top of the file. Nil when it isn't one of the loaded book's files.
    func smartResumeOffset(in item: PlayableContent?, from offset: TimeInterval, pausedAt: Date, heard: LoudnessTrace?) -> TimeInterval? {
        guard let current, let part = current.partIndex(of: item) else { return nil }
        let pause = Date.now.timeIntervalSince(pausedAt)
        let time = current.time(part: part, offset: offset)
        let fileStart = time - offset
        let target = SmartResume.resumeTime(from: time, afterPausing: pause, chapters: current.chapters, heard: heard?.shifted(by: fileStart))
        logSmartResume(from: time, to: target, afterPausing: pause, heard: heard != nil, chapters: current.chapters)
        return max(target - fileStart, 0)
    }

    /// Where and when a book on a speaker paused, for Smart Resume there
    /// (`smartResumeOnSpeaker`): this device's player stamps its own pause
    /// (`LocalPlaybackService.bookPause`); a speaker is only seen to have
    /// stopped, within a reading or two.
    @ObservationIgnored private var speakerPause: (at: Date, time: TimeInterval, coordinatorIP: String)?

    private func noteSpeakerPause(time: TimeInterval, playing: Bool, on controller: any PlaybackController) {
        guard let ip = controller.group?.coordinatorRoom.ip, !playing else {
            speakerPause = nil
            return
        }
        if wasPlaying {
            speakerPause = (.now, time, ip)
        } else if let pause = speakerPause, abs(time - pause.time) > Self.speakerPlaceSlack {
            // Moved while paused (a chapter, a scrub): it plays from there.
            speakerPause = nil
        }
    }

    /// How far a paused speaker's reading may wander and still be where it
    /// paused: its position comes back rounded to the second.
    private static let speakerPlaceSlack: TimeInterval = 2

    /// Smart Resume on a speaker: a book paused there goes back a little
    /// before it's told to play again, as on this device — by how long it
    /// was paused, never past the start of its chapter, into a pause in the
    /// speech when its file is downloaded here. Within the file playing
    /// only: a speaker moving to another file for a few seconds would be a
    /// new track. `SonosService` calls it before every Play it sends
    /// (`beforePlay`).
    func smartResumeOnSpeaker(ip: String) async {
        guard let pause = speakerPause, pause.coordinatorIP == ip, let current else { return }
        speakerPause = nil
        let controller = PlaybackRoute.shared.presented
        guard controller.group?.coordinatorRoom.ip == ip, !controller.isPlaying,
              let part = current.partIndex(of: controller.nowPlayingDisplay) else { return }
        let time = current.time(part: part, offset: controller.position())
        guard abs(time - pause.time) <= Self.speakerPlaceSlack else { return }
        let target = await resumeTime(for: current, from: time, afterPausing: Date.now.timeIntervalSince(pause.at))
        let location = current.timeline.location(at: target)
        guard target < time, location.part == part else { return }
        Self.log.info("smart resume on a speaker: back \(String(format: "%.1f", time - target)) s")
        await controller.seek(to: location.offset)
    }

    /// Smart Resume for a book played again from a kept place, `place`,
    /// left `pause` seconds ago: back a little, into a pause in the speech
    /// when the file it falls in is on this device, read around there (a
    /// few milliseconds). A streamed file isn't fetched for it: the plain
    /// rewind.
    private func resumeTime(for audiobook: Audiobook, from place: TimeInterval, afterPausing pause: TimeInterval) async -> TimeInterval {
        let plain = SmartResume.resumeTime(from: place, afterPausing: pause, chapters: audiobook.chapters)
        let part = audiobook.timeline.location(at: plain).part
        guard audiobook.parts.indices.contains(part),
              let url = DownloadManager.shared.localURL(for: audiobook.parts[part]) else {
            logSmartResume(from: place, to: plain, afterPausing: pause, heard: false, chapters: audiobook.chapters)
            return plain
        }
        let fileStart = audiobook.timeline.start(ofPart: part)
        // A few seconds around the plain rewind: as far as a pause is
        // looked for, and the voice around it.
        let from = plain - fileStart - 3
        let to = min(place, plain + 3) - fileStart
        let started = Date.now
        let heard = await Task.detached(priority: .userInitiated) {
            LoudnessTrace.reading(url, from: from, to: to)
        }.value
        let time = SmartResume.resumeTime(from: place, afterPausing: pause, chapters: audiobook.chapters, heard: heard?.shifted(by: fileStart))
        logSmartResume(from: place, to: time, afterPausing: pause, heard: heard != nil, chapters: audiobook.chapters, readIn: Date.now.timeIntervalSince(started))
        return time
    }

    private func logSmartResume(from time: TimeInterval, to target: TimeInterval, afterPausing pause: TimeInterval, heard: Bool, chapters: [AudiobookChapter], readIn: TimeInterval? = nil) {
        let plain = SmartResume.resumeTime(from: time, afterPausing: pause, chapters: chapters)
        let landing = !heard ? "nothing heard to look in" : target == plain ? "no pause in the speech near" : "a pause in the speech, \(String(format: "%+.2f", target - plain)) s from the plain rewind"
        let read = readIn.map { "; read the file in \(Int($0 * 1000)) ms" } ?? ""
        Self.log.notice("smart resume: back \(time - target, format: .fixed(precision: 2)) s to \(Int(target)) s after \(Int(pause)) s paused; \(landing, privacy: .public)\(read, privacy: .public)")
    }

    /// Resolves Plex's connection first when nothing has yet since launch,
    /// so the files of a book loaded on another network go on the best one
    /// here (`PlexAPI.onCurrentConnection`). A few seconds at most: with no
    /// network, Play isn't held up for it.
    private func prepareConnection(for audiobook: Audiobook) async {
        guard audiobook.book.content.service == .plex, !OfflineMode.shared.isActive else { return }
        _ = await Task { await PlexAPI.shared.prepareConnection() }.value(within: .seconds(3))
    }

    /// A book's file wouldn't load on this device, or broke off: a network
    /// lost on the way, a far seek over a slow one, an Audiobookshelf
    /// session the server ended. The queue player goes on to the next file
    /// by itself, which for a book is the next chapter, so the device's
    /// queue is parked at once and the book played again from where the
    /// file stopped (`offset` into it): a few times, waiting longer each
    /// time, then left there for Play. A new start opens a new
    /// Audiobookshelf session. False when it's left, for the caller to say
    /// it couldn't play.
    @discardableResult
    func fileFailed(_ item: PlayableContent, at offset: TimeInterval?) -> Bool {
        guard let current, let part = current.partIndex(of: item) else { return false }
        // The player's reading of the file, or the book's last, further in,
        // for a file that failed on its way there (it reads its top).
        var time = current.time(part: part, offset: offset ?? 0)
        if current.timeline.location(at: position).part == part {
            time = max(time, position)
        }
        // Parked so the queue player doesn't go on to the next file, the
        // next chapter. The sleep timer set stays, and while the file is to
        // be tried again so does the audio session: let go of in the
        // background, it can't be taken back to play.
        let retrying = failures < Self.retryDelays.count
        LocalPlaybackService.shared.park(keepingAudioSession: retrying, keepingSleepTimer: true)
        position = time
        arriving = time
        wasPlaying = false
        failedAt = time
        record(AudiobookProgress(position: time, duration: current.duration), of: current)
        guard failures < Self.retryDelays.count else {
            Self.log.error("book file \(part + 1) failed again at \(Int(time)) s; left there for Play")
            return false
        }
        let delay = Self.retryDelays[failures]
        failures += 1
        Self.log.notice("book file \(part + 1) failed at \(Int(time)) s; playing from there again in \(delay, privacy: .public) (try \(self.failures))")
        retry?.cancel()
        let book = current.book
        retry = Task { [weak self] in
            // With nothing playing, Cue in the background is suspended
            // before the retry comes round: the time is asked for.
            var background = UIBackgroundTaskIdentifier.invalid
            background = UIApplication.shared.beginBackgroundTask(withName: "Book file retry") {
                UIApplication.shared.endBackgroundTask(background)
                background = .invalid
            }
            defer {
                if background != .invalid {
                    UIApplication.shared.endBackgroundTask(background)
                }
            }
            try? await Task.sleep(for: delay)
            // The network may have changed under the file (home Wi‑Fi to
            // cellular): Plex's connection is raced again first, and the
            // file goes on the one that wins (`trackStreamURL`).
            if book.content.service == .plex {
                await PlexAPI.shared.refreshConnection()
            }
            // Not over something played meanwhile: the queue still parked
            // on the book's file, and the route still this device's.
            guard !Task.isCancelled, let self, let current = self.current, current.book.isSameBook(as: book),
                  PlaybackRoute.shared.group == nil,
                  self.contains(LocalPlaybackService.shared.nowPlaying) else { return }
            self.retry = nil
            await self.start(current, at: time, on: .device)
        }
        return true
    }

    /// A file failed and the book will be played again from there.
    @ObservationIgnored private var retry: Task<Void, Never>?
    /// Files failed in a row, with no stretch of listening between.
    @ObservationIgnored private var failures = 0
    /// Where the last file failed, until listening has gone well past it.
    @ObservationIgnored private var failedAt: TimeInterval?
    private static let retryDelays: [Duration] = [.seconds(1), .seconds(5), .seconds(15), .seconds(30)]

    /// A play, a move or the book left: any retry waiting is off, and the
    /// count starts over.
    private func forgetFailures() {
        retry?.cancel()
        retry = nil
        failures = 0
        failedAt = nil
    }

    /// Skips `seconds` (back when negative) through the book, across files.
    func skip(by seconds: TimeInterval) async {
        guard current != nil else { return }
        let controller = PlaybackRoute.shared.controller
        let now = readPosition(on: controller) ?? position
        await jump(to: now + seconds)
    }

    /// Sets the loaded book's speed, kept for that book alone.
    func setRate(_ rate: Double) {
        self.rate = rate
        guard let book = current?.book else { return }
        var rates = Self.bookRates
        rates[AudiobookProgressStore.key(for: book)] = rate == 1 ? nil : rate
        Self.bookRates = rates
    }

    private static var bookRates: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: ratesKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: ratesKey) }
    }

    /// The speed `book` was left at: 1× for one never changed.
    private static func rate(for book: PlayableContent?) -> Double {
        guard let book, let rate = bookRates[AudiobookProgressStore.key(for: book)], rate > 0 else { return 1 }
        return rate
    }

    // MARK: - Chapters

    /// The chapter after the one playing, from the last reading: nil in the
    /// last chapter. From the chapter rather than the place, so it changes
    /// only when the chapter does.
    var nextChapter: AudiobookChapter? {
        guard let chapters = current?.chapters else { return nil }
        guard let playing = currentChapter else { return chapters.first }
        return chapters.first { $0.start > playing.start }
    }

    /// Moves to the start of the next chapter.
    func skipToNextChapter() async {
        guard let current else { return }
        let now = readPosition(on: PlaybackRoute.shared.controller) ?? position
        guard let next = current.chapters.chapter(after: now) else { return }
        await jump(to: next.start)
    }

    /// Back to the start of the chapter playing, or, right at its start, of
    /// the one before: Previous for a song, by chapter.
    func skipToPreviousChapter() async {
        guard let current else { return }
        let now = readPosition(on: PlaybackRoute.shared.controller) ?? position
        guard let start = current.chapters.previousChapterStart(from: now) else { return }
        await jump(to: start)
    }

    // MARK: - Sleeping at the end of a chapter

    /// The book time End of Chapter pauses at. Nil when it isn't set.
    private(set) var sleepsAt: TimeInterval?

    /// Pauses at the end of the chapter playing. It runs on the player's
    /// own sleep timer (this device's, or the speaker's), set to the
    /// chapter's end at the speed playing and set again whenever the two
    /// drift apart — a pause, a skip, a new speed — so the timer's
    /// countdown shows wherever a sleep timer does.
    func sleepAtEndOfChapter() async {
        let controller = PlaybackRoute.shared.controller
        guard let current, let chapter = current.chapter(at: readPosition(on: controller) ?? position) else { return }
        sleepsAt = chapter.end
        await followChapterSleep(on: controller, force: true)
    }

    /// Forgets End of Chapter, for another timer chosen, or the timer off.
    /// The player's own timer is left to whoever set it.
    func forgetChapterSleep() {
        sleepsAt = nil
    }

    /// Keeps the player's sleep timer on the chapter's end. A timer that's
    /// gone, or past its time (a speaker's keeps the time it went off at),
    /// went off or was turned off: either way End of Chapter is done.
    private func followChapterSleep(on controller: any PlaybackController, force: Bool = false) async {
        guard let sleepsAt, let current else { return }
        guard let time = readPosition(on: controller) else { return }
        if !force, controller.sleepTimerEndDate.map({ $0 <= .now }) ?? true {
            self.sleepsAt = nil
            return
        }
        // Jumped past the chapter's end: the end of the chapter it's in now.
        var end = sleepsAt
        if time > end + 1, let chapter = current.chapter(at: time) {
            end = chapter.end
            self.sleepsAt = end
        }
        let speed = controller.group == nil ? rate : 1
        let remaining = max(end - time, 0) / speed
        let due = Date.now.addingTimeInterval(remaining)
        let drift = controller.sleepTimerEndDate.map { abs($0.timeIntervalSince(due)) } ?? .infinity
        if let group = controller.group {
            // A speaker's is set over the network: only for a real drift,
            // and only while it plays (its timer runs on through a pause).
            guard force || (controller.isPlaying && drift > 5) else { return }
            await SonosService.shared.sleepTimer(group: group, duration: .seconds(max(remaining.rounded(), 1)))
        } else {
            // This device's runs on through a pause too, so it's set again
            // while paused, and goes off only once playing reaches the end.
            guard force || drift > 1.5 else { return }
            LocalPlaybackService.shared.sleepTimer(.seconds(max(remaining.rounded(), 1)))
        }
    }

    /// Starts `audiobook` at book time `time`, at `target`. False when it
    /// didn't start (said in an alert).
    @discardableResult
    private func start(_ audiobook: Audiobook, at time: TimeInterval, on target: Target = .route) async -> Bool {
        // A switch still carrying the last queue across would go on filling
        // the speaker's queue under the book's files.
        await PlaybackRoute.shared.endHandOff()
        var audiobook = audiobook
        // Audiobookshelf streams belong to a listening session, opened
        // for each play; its files' URLs come from it.
        // A book downloaded whole plays from its files without one: offline,
        // or when the server won't open a session.
        if audiobook.book.content.service == .audiobookshelf {
            let downloaded = AudiobookDownloads.hasAllFiles(audiobook)
            if downloaded, OfflineMode.shared.isActive {
                Self.log.notice("playing \(audiobook.book.title, privacy: .public)'s downloaded files offline")
            } else if let opened = await AudiobookLibrary.openAudiobookshelfSession(for: audiobook) {
                audiobook = opened
            } else if downloaded {
                Self.log.notice("no session for \(audiobook.book.title, privacy: .public); playing its downloaded files")
            } else {
                AlertService.shared.showAlert(with: "Couldn't start “\(audiobook.book.title)”", imageName: "exclamationmark.triangle")
                return false
            }
        }
        let location = audiobook.timeline.location(at: time)
        // The music the book takes this device's player from is set aside,
        // to go back to (`returnToMusic`). A queue holding a book's files
        // isn't music, whatever plays in front of it (a station, a song
        // played next): the music set aside before it stands.
        let local = LocalPlaybackService.shared
        let isBookFile = { [self, audiobook] (item: PlayableContent) in
            audiobook.partIndex(of: item) != nil || contains(item) || leftBook?.partIDs.contains(item.id) == true
        }
        let replacesMusic = local.isActive && !local.queue.contains(where: isBookFile)
        // What was loaded, for a start that fails before the book gets to
        // the player (`undoStart`).
        let previous = current
        let previousLeft = leftBook
        setCurrent(audiobook)
        if leftBook?.book.isSameBook(as: audiobook.book) == true {
            leftBook = nil
        }
        position = time
        arriving = time
        graceUntil = .now.addingTimeInterval(15)
        misses = 0

        var group: GroupRoom? = switch target {
        case .route: PlaybackRoute.shared.group
        case .device: nil
        case let .group(group): group
        }
        // A book in the Files folder plays here alone, since no speaker can
        // reach it. The route comes to this device, so the player shows the
        // book and is what this follows; a speaker keeps its own queue.
        if audiobook.book.content.service.playsOnDeviceOnly {
            if group != nil || PlaybackRoute.shared.destination != .device {
                PlaybackRoute.shared.switchTo(.device, carrying: false)
            }
            group = nil
        }
        if !OfflineMode.shared.isActive, let group {
            guard await playOnSpeaker(audiobook, part: location.part, offset: location.offset, group: group) else {
                undoStart(of: audiobook, previous: previous, previousLeft: previousLeft, onDevice: false)
                return false
            }
            return true
        }
        if replacesMusic {
            local.setQueueAside()
        }
        // A book plays its files in order, once: the music's repeat goes
        // aside with the music (a new queue isn't shuffled).
        local.setRepeatMode(.off)
        do {
            try await local.play(audiobook.parts, startingAt: location.part, from: location.offset)
            return true
        } catch {
            Self.log.error("device play failed: \(error.localizedDescription, privacy: .public)")
            AlertService.shared.showAlert(with: "Couldn't play “\(audiobook.book.title)” on this device", imageName: "exclamationmark.triangle")
            undoStart(of: audiobook, previous: previous, previousLeft: previousLeft, onDevice: true)
            return false
        }
    }

    /// Puts back what was loaded before a start of `audiobook` that failed
    /// short of the player: the book wasn't heard, so it isn't left, nor
    /// offered back, nor a place in its history. On this device a play that
    /// got as far as putting the book's files in the queue stands, paused
    /// there for Play to try again (`resumeOnDevice`).
    private func undoStart(of audiobook: Audiobook, previous: Audiobook?, previousLeft: LeftBook?, onDevice: Bool) {
        guard current?.book.isSameBook(as: audiobook.book) == true else { return }
        if onDevice, LocalPlaybackService.shared.queue.contains(where: { audiobook.partIndex(of: $0) != nil }) { return }
        Self.log.notice("start of \(audiobook.book.title, privacy: .public) undone: it never reached the player")
        setCurrent(previous)
        leftBook = previousLeft
        if previous != nil {
            graceUntil = .now.addingTimeInterval(15)
            misses = 0
        }
    }

    // MARK: - Between a book and music

    /// The book last left for something else, to offer back from the music
    /// player, and its files' IDs, to know them in the queue. Nil once it
    /// plays again. Kept through a relaunch.
    struct LeftBook: Codable, Equatable {
        let book: PlayableContent
        let partIDs: Set<String>
    }

    private(set) var leftBook: LeftBook? {
        didSet {
            guard leftBook != oldValue else { return }
            UserDefaults.standard.set(leftBook.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.leftBookKey)
        }
    }

    /// The book Back to Book offers from the music: the one last left,
    /// unless it was finished since (a tap would start it over).
    var bookToReturnTo: PlayableContent? {
        guard let leftBook, AudiobookProgressStore.shared.progress(for: leftBook.book)?.isFinished != true else { return nil }
        return leftBook.book
    }

    private static let leftBookKey = "dance.cue.audiobookLeftBook"

    /// The music the book was started over, while the book plays on this
    /// device: what Back to Music and Where You Left Off bring back. Nil
    /// while the route is a speaker, where the device's queue isn't what's
    /// heard and its music would play beside the book.
    var musicSetAside: LocalPlaybackService.SetAsideQueue? {
        let local = LocalPlaybackService.shared
        guard PlaybackRoute.shared.destination == .device, contains(local.nowPlaying) else { return nil }
        return local.setAsideQueue
    }

    /// `musicSetAside` while Where You Left Off shows it: not once it's
    /// swiped away, or as Play takes it back.
    var musicLeftOff: LocalPlaybackService.SetAsideQueue? {
        musicSetAside.flatMap { $0.isDismissed == true ? nil : $0 }
    }

    /// Leaves the book for the music queue it was started over, at the song
    /// and spot it was left on (`LocalPlaybackService.setAsideQueue`). The
    /// book keeps its place, and the music player offers it back. Throws
    /// what kept the music from playing, which `alert` also says on the
    /// phone; CarPlay says it on the car's screen instead.
    func returnToMusic(alert: Bool = true) async throws {
        // A file that failed waits to play again: not over the music.
        forgetFailures()
        if let current {
            leftBook = LeftBook(book: current.book, partIDs: Set(current.parts.map(\.id)))
            // The place as it is now, not as the last follow read it: Back
            // to Book a moment later picks up here.
            record(AudiobookProgress(position: heardPosition, duration: current.duration), of: current)
        }
        do {
            try await LocalPlaybackService.shared.returnToSetAsideQueue()
        } catch {
            Self.log.error("back to music failed: \(error.localizedDescription, privacy: .public)")
            if alert {
                AlertService.shared.showAlert(with: "Couldn't go back to your music", imageName: "exclamationmark.triangle")
            }
            throw error
        }
    }

    /// Opens a listening session for the loaded Audiobookshelf book when
    /// its files in `items` are about to go to a speaker and it holds none
    /// (it was started from its download, or picked up long after): a
    /// speaker is given the session's URLs, which need no sign-in, and
    /// without one, file URLs signed with a token that runs out in an hour,
    /// when the speaker would stop.
    func prepareForSpeaker(_ items: [PlayableContent]) async {
        guard let current, current.book.content.service == .audiobookshelf, !OfflineMode.shared.isActive,
              !AudiobookshelfAPI.hasOpenSession(for: current.book.content.id),
              items.contains(where: { current.partIndex(of: $0) != nil }) else { return }
        if await AudiobookshelfAPI.shared.startSession(itemID: current.book.content.id) == nil {
            Self.log.error("no session for \(current.book.title, privacy: .public) to hand to a speaker")
        }
    }

    /// The speaker's queue becomes the book's files from `part` on, the
    /// first set `offset` in before it starts (see `SonosService.cue`).
    private func playOnSpeaker(_ audiobook: Audiobook, part: Int, offset: TimeInterval, group: GroupRoom) async -> Bool {
        let sonos = SonosService.shared
        LocalPlaybackService.shared.park()
        let first = audiobook.parts[part]
        do {
            // In order, once: not the shuffle or repeat the speaker was left
            // on for music.
            if group.playMode != .normal {
                await sonos.setPlayMode(group.ip, mode: .normal)
            }
            let landed = try await sonos.cue(first, on: group, at: offset)
            await sonos.play(ip: group.ip)
            if !landed, offset > 0 {
                _ = await sonos.waitUntilSettled(ip: group.ip)
                await sonos.seek(to: offset * 1000, on: group)
            }
            group.coordinatorRoom.beginSeek(to: offset * 1000)
            let rest = Array(audiobook.parts.dropFirst(part + 1))
            if !rest.isEmpty {
                do {
                    try await sonos.queue(contents: rest, group: group, position: .end)
                } catch {
                    // Playing already: the files after it are what's missing.
                    Self.log.error("speaker play: the files after the first didn't queue: \(error.localizedDescription, privacy: .public)")
                }
            }
            return true
        } catch {
            Self.log.error("speaker play failed: \(error.localizedDescription, privacy: .public)")
            AlertService.shared.showAlert(with: error.localizedDescription, imageName: "exclamationmark.triangle")
            return false
        }
    }

    // MARK: - Following playback

    private func startMonitoring() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
    }

    /// Where the loaded book is now: the route's reading, not the last one
    /// the follow took.
    var heardPosition: TimeInterval {
        readPosition(on: PlaybackRoute.shared.controller) ?? position
    }

    /// The book time `controller` is at, when it's playing the book: where
    /// it was sent while it's still loading the file there.
    private func readPosition(on controller: any PlaybackController) -> TimeInterval? {
        guard let current, let part = current.partIndex(of: controller.nowPlayingDisplay) else { return nil }
        let offset = controller.position()
        let time = current.time(part: part, offset: offset)
        if let arriving, isStillArriving(time: time, offset: offset, playing: controller.isPlaying) { return arriving }
        return time
    }

    /// Whether a reading at book time `time`, `offset` into its file, is the
    /// player still on its way to `arriving`: still at the place `jump` left
    /// just after it was sent (a seek in the file playing reads the old
    /// place, playing, until it lands, and a chapter picked flicked back to
    /// the one before for a moment), loading at the top of a file short of
    /// it, or stopped anywhere else (the queue parked after a file failed,
    /// on whichever file the queue player had gone on to). A reading
    /// anywhere else just after a jump is a real move (a scrub on the Lock
    /// Screen or in the car), not the seek.
    private func isStillArriving(time: TimeInterval, offset: TimeInterval, playing: Bool) -> Bool {
        guard let arriving, abs(time - arriving) > Self.arrivalTolerance else { return false }
        if let leaving, abs(time - leaving) <= Self.arrivalTolerance,
           Date.now.timeIntervalSince(arrivingSince) < Self.arrivalGrace {
            return true
        }
        return !playing || (time < arriving && offset < Self.arrivalTolerance)
    }

    private func tick() {
        guard let current else { return stopMonitoring() }
        let route = PlaybackRoute.shared
        // Mid hand-off the presented song is the hold's; wait for the
        // target.
        guard !route.isHolding else { return }
        let controller = route.presented
        guard let part = current.partIndex(of: controller.nowPlayingDisplay) else {
            // A song played next, in a queue that still holds the book: the
            // book carries on after it.
            if controller.group == nil,
               LocalPlaybackService.shared.queue.contains(where: { current.partIndex(of: $0) != nil }) {
                misses = 0
                return
            }
            // Something else has the player — or the book is still on its
            // way into it.
            if controller.nowPlayingDisplay != nil, Date.now > graceUntil {
                misses += 1
                if misses >= 3 { end() }
            }
            return
        }
        misses = 0
        let offset = controller.position()
        let time = current.time(part: part, offset: offset)
        let playing = controller.isPlaying
        if let arriving {
            guard !isStillArriving(time: time, offset: offset, playing: playing) else {
                if heldBackOnWayTo != arriving {
                    heldBackOnWayTo = arriving
                    Self.log.notice("on its way to \(Int(arriving)) s; held back a reading of \(Int(time)) s (file \(part + 1), \(playing ? "playing" : "stopped", privacy: .public))")
                }
                return
            }
            self.arriving = nil
            Self.log.notice("got to \(Int(time)) s (file \(part + 1), \(Int(offset)) s in), sent to \(Int(arriving)) s")
        }
        // The queue on to another file: at the end of the last, or not.
        if let lastPart, lastPart != part {
            let lengths = current.timeline.partDurations
            let length = lengths.indices.contains(lastPart) ? lengths[lastPart] : 0
            Self.log.notice("file \(lastPart + 1) → file \(part + 1); file \(lastPart + 1) was \(Int(self.lastOffset)) of \(Int(length)) s in")
        }
        lastPart = part
        lastOffset = offset
        // A mark set the place: what the player says is kept only once it
        // plays again.
        if holdsReadings {
            guard playing else {
                wasPlaying = playing
                return
            }
            holdsReadings = false
            lastReading = nil
        }
        // Listening has gone well past the file that failed.
        if let failedAt, playing, time > failedAt + 30 {
            self.failedAt = nil
            failures = 0
        }
        let finished = time >= current.duration - AudiobookProgress.finishedMargin && part == current.parts.count - 1
        // At the end the player goes back to the top of the queue and
        // waits there. That isn't the listener starting over — until they
        // press Play, the book stays finished.
        if finished {
            reachedEnd = true
        } else if reachedEnd {
            guard playing else {
                // Back at the top of a file, stopped: the queue ran out.
                if controller.position() < 5 { reportFinished(current) }
                wasPlaying = playing
                return
            }
            reachedEnd = false
            finishReported = false
        }
        position = time
        notePlace(time: time, playing: playing, of: current)
        noteSpeakerPause(time: time, playing: playing, on: controller)
        let paused = wasPlaying && !playing
        let reading = AudiobookProgress(position: time, duration: current.duration, isFinished: finished)
        if lastStoredPosition == nil, !playing, !paused {
            // The first reading since the book was loaded, of a player
            // that isn't playing: the queue as the app left it at launch.
            // That's where it was, not listening, so it's only the mark a
            // move is measured from; what's kept may be newer (another
            // player's place, through the server).
            lastStoredPosition = time
        } else if abs(time - (lastStoredPosition ?? -.infinity)) >= Self.storeInterval || paused {
            // Every few seconds of listening, not every reading: each write
            // redraws every row showing a book's progress.
            record(reading, of: current)
        } else if playing {
            unrecorded = reading
        }
        syncServer(current, part: part, time: time, playing: playing, onSpeaker: controller.group != nil)
        wasPlaying = playing
        if sleepsAt != nil {
            Task { await followChapterSleep(on: controller) }
        }
    }

    /// Keeps a pause in the place history, and a reading far from where
    /// listening since the last one would have got to: a move made some way
    /// other than `jump` (the scrubber, the car, the Lock Screen), or one
    /// nobody asked for. Where it moved from is the place to go back to.
    private func notePlace(time: TimeInterval, playing: Bool, of audiobook: Audiobook) {
        let places = AudiobookPlaceHistory.shared
        if let last = lastReading {
            let listened = last.playing ? Date.now.timeIntervalSince(last.at) * max(rate, 1) : 0
            if time > last.time + listened + Self.placeJump || time < last.time - Self.placeJump {
                Self.log.notice("moved from \(Int(last.time)) s to \(Int(time)) s; kept in the place history")
                places.record(.jumpedFrom, at: last.time, to: time, for: audiobook.book)
            }
        }
        if wasPlaying, !playing {
            places.record(.paused, at: time, for: audiobook.book)
        }
        lastReading = (time, .now, playing)
    }

    /// Tells the book's server where it is: every few seconds while playing,
    /// and once on a pause.
    private func syncServer(_ audiobook: Audiobook, part: Int, time: TimeInterval, playing: Bool, onSpeaker: Bool) {
        // Offline the server isn't asked, even with a network up (the
        // listener's switch). Audiobookshelf's listening is kept for it
        // meanwhile, a local session a day sent once it answers again
        // (`AudiobookshelfAPI.noteUnsentListening`); a place goes to either
        // server when the book is next read (`AudiobookLibrary.sendNewerPlace`).
        let offline = OfflineMode.shared.isActive
        guard !offline || audiobook.book.content.service == .audiobookshelf else { return }
        let paused = wasPlaying && !playing
        guard paused || (playing && Date.now.timeIntervalSince(lastServerSync) >= Self.serverSyncInterval) else { return }
        // What was heard since the last sync, for the server's listening
        // stats; a jump isn't listening.
        let listened = lastServerPosition.map { min(max(time - $0, 0), Date.now.timeIntervalSince(lastServerSync) * rate + 1) } ?? 0
        lastServerSync = .now
        lastServerPosition = time
        switch audiobook.book.content.service {
        case .audiobookshelf:
            let itemID = audiobook.book.content.id
            let duration = audiobook.duration
            if offline {
                AudiobookshelfAPI.noteUnsentListening(itemID: itemID, currentTime: time, timeListened: listened, duration: duration)
                return
            }
            Task {
                await AudiobookshelfAPI.shared.sync(itemID: itemID, currentTime: time, timeListened: listened, duration: duration)
            }
        case .plex:
            // This device reports its own plays (`PlayReporter`); a speaker
            // doesn't, so its place goes from here.
            guard onSpeaker, let key = audiobook.parts[part].plexRatingKey else { return }
            let offset = time - audiobook.timeline.start(ofPart: part)
            let length = audiobook.timeline.partDurations[part]
            Task {
                await PlexAPI.shared.reportTimeline(ratingKey: key, state: playing ? .playing : .paused, time: offset, duration: length)
            }
        default:
            break
        }
    }

    /// Says the book is finished, once: the last sync can fall short of the
    /// server's own finish line (Audiobookshelf's is ten seconds from the
    /// end). Plex counts the last file played from its final report.
    private func reportFinished(_ audiobook: Audiobook) {
        guard !finishReported else { return }
        finishReported = true
        AudiobookProgressStore.shared.record(
            AudiobookProgress(position: audiobook.duration, duration: audiobook.duration, isFinished: true),
            for: audiobook.book
        )
        // Offline the server isn't asked; the finish, kept here, goes to it
        // when the book is next opened (`AudiobookLibrary.load`).
        guard audiobook.book.content.service == .audiobookshelf, !OfflineMode.shared.isActive else { return }
        let itemID = audiobook.book.content.id
        let duration = audiobook.duration
        Task {
            await AudiobookshelfAPI.shared.updateProgress(itemID: itemID, currentTime: duration, duration: duration, isFinished: true)
        }
    }

    /// Keeps `reading` as this device's place in `audiobook`.
    private func record(_ reading: AudiobookProgress, of audiobook: Audiobook) {
        lastStoredPosition = reading.position
        unrecorded = nil
        AudiobookProgressStore.shared.record(reading, for: audiobook.book)
    }

    /// Keeps what was heard of the loaded book since its place was last
    /// kept: for the book being left, or the app going to the background.
    private func keepUnrecorded() {
        guard let current, let unrecorded else { return }
        record(unrecorded, of: current)
    }

    /// Writes what's held, for the app leaving the foreground.
    private func flush() {
        keepUnrecorded()
        AudiobookProgressStore.shared.save()
        AudiobookPlaceHistory.shared.save()
        BookWordLookups.shared.save()
    }

    /// Steps aside for a mark that sets `book`'s place (Mark as Finished,
    /// Mark as Unfinished), when it's the book loaded: what was heard is
    /// kept first, the book is stopped, and nothing it reads is kept again
    /// until it plays, or the next reading would put back where it was
    /// playing. On this device the player is taken down, so Play starts
    /// from the marked place (`resumeOnDevice`), not where it stopped.
    func noteMarked(_ book: PlayableContent) async {
        guard let current, current.book.isSameBook(as: book) else { return }
        keepUnrecorded()
        holdsReadings = true
        let controller = PlaybackRoute.shared.controller
        guard isPlayingBook(on: controller) else { return }
        if controller.group == nil {
            LocalPlaybackService.shared.park()
        } else if controller.isPlaying {
            await controller.togglePlayback()
        }
    }

    /// Another device moved `book`'s place to `place` (the Apple Watch,
    /// listened to since): when it's the book loaded here and not playing,
    /// it gives way, so Play picks up there rather than where this device
    /// paused. In the same file the player moves there; in another, this
    /// device's player is taken down (Play then starts from the kept place,
    /// `resumeOnDevice`) without telling Plex where it had paused, which
    /// would take the book back. Nothing read here is kept until it plays,
    /// a session closed later closes at the new place, and the server hears
    /// of it now. One playing here keeps playing; its own place, newer,
    /// goes to the watch.
    func notePlaceMoved(_ book: PlayableContent, to place: AudiobookProgress) async {
        guard let current, current.book.isSameBook(as: book) else { return }
        let controller = PlaybackRoute.shared.controller
        guard !controller.isPlaying else { return }
        Self.log.notice("\(book.title, privacy: .public): its place moved on another device, to \(Int(place.position)) s; Play starts there")
        unrecorded = nil
        holdsReadings = true
        lastReading = nil
        position = place.position
        lastStoredPosition = place.position
        lastServerPosition = place.position
        let location = current.timeline.location(at: place.resumePosition)
        if isPlayingBook(on: controller) {
            if current.partIndex(of: controller.nowPlayingDisplay) == location.part {
                await controller.seek(to: location.offset)
            } else if controller.group == nil {
                PlayReporter.shared.forget()
                LocalPlaybackService.shared.park()
            }
        }
        if !OfflineMode.shared.isActive {
            AudiobookLibrary.sendNewerPlace(of: current)
        }
    }

    /// The book is no longer what's playing.
    private func end() {
        guard let current else { return }
        Self.log.notice("book left: \(current.book.title, privacy: .public)")
        // After a relaunch the book is known before anything has read its
        // place, and `position` is still 0 until it plays: left then, the
        // place it was left at is the one kept, not the top of the book.
        let left = position > 0 ? position : AudiobookProgressStore.shared.progress(for: current.book)?.position ?? 0
        // What took the player, for the break in the book's history.
        let next = PlaybackRoute.shared.presented.nowPlayingDisplay?.title
        AudiobookPlaceHistory.shared.record(.left, at: left, for: current.book, note: next)
        leftBook = LeftBook(book: current.book, partIDs: Set(current.parts.map(\.id)))
        // Offline the session is left to lapse on the server.
        if current.book.content.service == .audiobookshelf, !OfflineMode.shared.isActive {
            let itemID = current.book.content.id
            // A finished book closes at its end, not where the player
            // rewound to.
            let time = reachedEnd ? current.duration : position
            let duration = current.duration
            Task { await AudiobookshelfAPI.shared.closeSession(itemID: itemID, currentTime: time, duration: duration) }
        }
        setCurrent(nil)
        sleepsAt = nil
        forgetFailures()
        stopMonitoring()
        flush()
    }

    private func setCurrent(_ audiobook: Audiobook?) {
        // The book loaded until now keeps what was heard of it.
        keepUnrecorded()
        current = audiobook
        updateChapter()
        rate = Self.rate(for: audiobook?.book)
        lastServerSync = .distantPast
        lastServerPosition = nil
        lastStoredPosition = nil
        arriving = nil
        lastPart = nil
        lastReading = nil
        reachedEnd = false
        finishReported = false
        holdsReadings = false
        wasPlaying = false
        Self.saveCurrent(audiobook)
        if audiobook != nil { startMonitoring() }
    }

    // MARK: - Surviving a relaunch

    /// The loaded book is kept beside the device queue, which holds its
    /// files, so a relaunch still knows they're a book.
    private static var currentURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AudiobookCurrent.json")
    }

    private static func loadCurrent() -> Audiobook? {
        guard let url = currentURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Audiobook.self, from: data)
    }

    private static func saveCurrent(_ audiobook: Audiobook?) {
        guard let url = currentURL else { return }
        guard let audiobook, let data = try? JSONEncoder().encode(audiobook) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}
