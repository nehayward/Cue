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
    private(set) var position: TimeInterval = 0
    /// A book is being read from its server to play.
    private(set) var isLoading = false

    /// How fast books play on this device, 1 being normal. Speakers play
    /// at 1× whatever this says: Sonos has no other speed.
    private(set) var rate: Double

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
    /// The book was heard to its end, and nothing has played since.
    @ObservationIgnored private var reachedEnd = false
    /// The server has been told the book is finished.
    @ObservationIgnored private var finishReported = false
    @ObservationIgnored private var backgroundObserver: (any NSObjectProtocol)?

    private static let rateKey = "dance.cue.audiobookRate"
    private static let serverSyncInterval: TimeInterval = 15
    private static let storeInterval: TimeInterval = 10

    private init() {
        let stored = UserDefaults.standard.double(forKey: Self.rateKey)
        rate = stored > 0 ? stored : 1
        current = Self.loadCurrent()
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

    /// Whether `item` is one of the loaded book's files.
    func contains(_ item: PlayableContent?) -> Bool {
        current?.partIndex(of: item) != nil
    }

    /// The rate this device plays `item` at: the book speed for a book's
    /// file, normal for anything else.
    func playbackRate(for item: PlayableContent?) -> Float {
        contains(item) ? Float(rate) : 1
    }

    /// The chapter playing, from the last reading.
    var currentChapter: AudiobookChapter? {
        current?.chapter(at: position)
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
        let startTime = min(max(time ?? AudiobookLibrary.progress(for: audiobook)?.resumePosition ?? 0, 0), audiobook.duration)
        await start(audiobook, at: startTime, on: target)
        // The book, not its files: Recently Played opens its page.
        PlayHistoryService.shared.record(audiobook.book)
    }

    /// Moves to `time` in the loaded book: a seek within the file playing,
    /// else the file it falls in, from there.
    func jump(to time: TimeInterval) async {
        guard let current else { return }
        let target = min(max(time, 0), current.duration)
        let location = current.timeline.location(at: target)
        let controller = PlaybackRoute.shared.controller
        position = target
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

    /// A book's file wouldn't load on this device. An Audiobookshelf file
    /// streams through its session, which the server may have ended (a
    /// restart does): a new session, and the book again from where it was.
    /// Once a minute at most, so a server that's simply down isn't asked
    /// over and over.
    func fileFailed(_ item: PlayableContent) {
        guard let current, current.book.content.service == .audiobookshelf, contains(item),
              Date.now.timeIntervalSince(lastRecovery) > 60 else { return }
        lastRecovery = .now
        let time = position
        Self.log.notice("book file failed; opening a new session")
        Task { await start(current, at: time, on: .device) }
    }

    @ObservationIgnored private var lastRecovery: Date = .distantPast

    /// Skips `seconds` (back when negative) through the book, across files.
    func skip(by seconds: TimeInterval) async {
        guard current != nil else { return }
        let controller = PlaybackRoute.shared.controller
        let now = readPosition(on: controller) ?? position
        await jump(to: now + seconds)
    }

    func setRate(_ rate: Double) {
        self.rate = rate
        UserDefaults.standard.set(rate, forKey: Self.rateKey)
    }

    // MARK: - Chapters

    /// The chapter after the one playing, from the last reading: nil in the
    /// last chapter.
    var nextChapter: AudiobookChapter? {
        current?.chapters.chapter(after: position)
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
    /// gone means it went off, or was turned off: either way End of Chapter
    /// is done.
    private func followChapterSleep(on controller: any PlaybackController, force: Bool = false) async {
        guard let sleepsAt, let current else { return }
        guard let time = readPosition(on: controller) else { return }
        if !force, controller.sleepTimerEndDate == nil {
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

    /// Starts `audiobook` at book time `time`, at `target`.
    private func start(_ audiobook: Audiobook, at time: TimeInterval, on target: Target = .route) async {
        var audiobook = audiobook
        // Audiobookshelf streams belong to a listening session, opened
        // for each play; its files' URLs come from it.
        if audiobook.book.content.service == .audiobookshelf {
            guard let opened = await AudiobookLibrary.openAudiobookshelfSession(for: audiobook) else {
                AlertService.shared.showAlert(with: "Couldn't start “\(audiobook.book.title)”", imageName: "exclamationmark.triangle")
                return
            }
            audiobook = opened
        }
        let location = audiobook.timeline.location(at: time)
        setCurrent(audiobook)
        position = time
        graceUntil = .now.addingTimeInterval(15)
        misses = 0

        let group: GroupRoom? = switch target {
        case .route: PlaybackRoute.shared.group
        case .device: nil
        case let .group(group): group
        }
        if !OfflineMode.shared.isActive, let group {
            await playOnSpeaker(audiobook, part: location.part, offset: location.offset, group: group)
        } else {
            do {
                try await LocalPlaybackService.shared.play(audiobook.parts, startingAt: location.part, from: location.offset)
            } catch {
                Self.log.error("device play failed: \(error.localizedDescription, privacy: .public)")
                AlertService.shared.showAlert(with: "Couldn't play “\(audiobook.book.title)” on this device", imageName: "exclamationmark.triangle")
            }
        }
    }

    /// The speaker's queue becomes the book's files from `part` on, the
    /// first set `offset` in before it starts (see `SonosService.cue`).
    private func playOnSpeaker(_ audiobook: Audiobook, part: Int, offset: TimeInterval, group: GroupRoom) async {
        let sonos = SonosService.shared
        LocalPlaybackService.shared.park()
        let first = audiobook.parts[part]
        do {
            let landed = try await sonos.cue(first, on: group, at: offset)
            await sonos.play(ip: group.ip)
            if !landed, offset > 0 {
                _ = await sonos.waitUntilSettled(ip: group.ip)
                await sonos.seek(to: offset * 1000, on: group)
            }
            group.coordinatorRoom.beginSeek(to: offset * 1000)
            let rest = Array(audiobook.parts.dropFirst(part + 1))
            if !rest.isEmpty {
                try await sonos.queue(contents: rest, group: group, position: .end)
            }
        } catch {
            Self.log.error("speaker play failed: \(error.localizedDescription, privacy: .public)")
            AlertService.shared.showAlert(with: error.localizedDescription, imageName: "exclamationmark.triangle")
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

    /// The book time `controller` is at, when it's playing the book.
    private func readPosition(on controller: any PlaybackController) -> TimeInterval? {
        guard let current, let part = current.partIndex(of: controller.nowPlayingDisplay) else { return nil }
        return current.time(part: part, offset: controller.position())
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
        let time = current.time(part: part, offset: controller.position())
        let playing = controller.isPlaying
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
        // Every few seconds of listening, not every reading: each write
        // redraws every row showing a book's progress.
        let paused = wasPlaying && !playing
        if abs(time - (lastStoredPosition ?? -.infinity)) >= Self.storeInterval || paused {
            lastStoredPosition = time
            AudiobookProgressStore.shared.record(
                AudiobookProgress(position: time, duration: current.duration, isFinished: finished),
                for: current.book
            )
        }
        syncServer(current, part: part, time: time, playing: playing, onSpeaker: controller.group != nil)
        wasPlaying = playing
        if sleepsAt != nil {
            Task { await followChapterSleep(on: controller) }
        }
    }

    /// Tells the book's server where it is: every few seconds while playing,
    /// and once on a pause.
    private func syncServer(_ audiobook: Audiobook, part: Int, time: TimeInterval, playing: Bool, onSpeaker: Bool) {
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
        guard audiobook.book.content.service == .audiobookshelf else { return }
        let itemID = audiobook.book.content.id
        let duration = audiobook.duration
        Task {
            await AudiobookshelfAPI.shared.updateProgress(itemID: itemID, currentTime: duration, duration: duration, isFinished: true)
        }
    }

    /// Writes what's held, for the app leaving the foreground.
    private func flush() {
        AudiobookProgressStore.shared.save()
    }

    /// The book is no longer what's playing.
    private func end() {
        guard let current else { return }
        Self.log.notice("book left: \(current.book.title, privacy: .public)")
        if current.book.content.service == .audiobookshelf {
            let itemID = current.book.content.id
            // A finished book closes at its end, not where the player
            // rewound to.
            let time = reachedEnd ? current.duration : position
            let duration = current.duration
            Task { await AudiobookshelfAPI.shared.closeSession(itemID: itemID, currentTime: time, duration: duration) }
        }
        setCurrent(nil)
        sleepsAt = nil
        stopMonitoring()
        flush()
    }

    private func setCurrent(_ audiobook: Audiobook?) {
        current = audiobook
        lastServerSync = .distantPast
        lastServerPosition = nil
        lastStoredPosition = nil
        reachedEnd = false
        finishReported = false
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
