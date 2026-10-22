import AVFoundation
import MediaPlayer
import MusicSearchKit
import Observation
import OSLog
import UIKit
import WatchKit
import WatchSync

/// Plays what's on the watch, to headphones or a speaker.
///
/// A long-form audio session: the system offers its route picker when
/// nothing's connected, playback carries on with the screen off, and the
/// song shows in Now Playing, where the Digital Crown sets the volume. Only
/// songs that are here play; a queue is the downloaded songs of an album,
/// playlist, artist or the songs added one at a time.
///
/// A book plays as a book (`playBook`): its files are the queue, from where
/// it was left (`WatchBookStore`), at its own speed, with skips back 15 s
/// and ahead 30 s in place of Previous and Next. Now Playing shows its
/// chapter as Apple Books does: the chapter's title over the book's, and
/// the time into the chapter against the chapter's length, moved on the
/// moment the next one starts (a boundary observer at its start). Its place is kept every few seconds as it plays,
/// and at once on a pause. A file not here yet stops it there rather than
/// skipping part of the story.
@MainActor
@Observable
final class WatchPlayer {
    static let shared = WatchPlayer()

    private(set) var queue: [WatchSong] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    /// The book playing, when it's a book: its files are the queue.
    private(set) var book: WatchPick?
    /// Where the book is, in book time: kept as it plays, every few
    /// seconds, and on every move.
    private(set) var bookPosition: TimeInterval = 0
    /// How fast it plays: a book's own speed, 1 for music.
    private(set) var rate: Double = 1

    var current: WatchSong? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    /// What the widgets and the home screen show: the book, or the song.
    var nowPlayingTitle: String? {
        book?.title ?? current?.title
    }

    var nowPlayingArtist: String? {
        book.map(\.subtitle) ?? current?.artist
    }

    static let skipBack: TimeInterval = 15
    static let skipAhead: TimeInterval = 30

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var commandsConfigured = false
    /// The book's files laid end to end.
    @ObservationIgnored private var timeline: AudiobookTimeline?
    /// Where in the file a load is on its way to, until the file is ready
    /// to be moved there: until then the player reads the file's top.
    @ObservationIgnored private var pendingOffset: TimeInterval?
    /// Whether that load plays once it gets there.
    @ObservationIgnored private var pendingPlay = false
    /// When the book paused, and where (book time), for Smart Resume: Play
    /// goes back a little first, further the longer it rested. Nil while it
    /// plays.
    @ObservationIgnored private var bookPause: (at: Date, time: TimeInterval)?
    /// How loud the file was up to that pause, on the book's clock: read in
    /// the background as it paused (`hearBeforePause`), so Play never waits
    /// on it.
    @ObservationIgnored private var heardBeforePause: (pausedAt: Date, trace: LoudnessTrace)?
    @ObservationIgnored private var hearing: Task<Void, Never>?
    /// The chapter Now Playing last showed.
    @ObservationIgnored private var shownChapter: Int?
    /// Fires where the next chapter starts in the file playing, to show it.
    @ObservationIgnored private var chapterObserver: Any?
    @ObservationIgnored private let logger = Logger(subsystem: "dance.cue.watch", category: "Player")

    private init() {
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in
                guard let self else { return }
                let paused = self.isPlaying && !playing
                self.isPlaying = playing
                // A pause keeps the book's place, and tells the iPhone; not
                // the pause a load makes on its way to a place.
                if paused, self.book != nil, self.pendingOffset == nil {
                    self.notePlace(tellPhoneNow: true)
                    self.bookPause = (at: Date.now, time: self.bookPosition)
                    self.hearBeforePause()
                } else if playing {
                    self.forgetPause()
                }
                self.updateNowPlaying()
                WidgetStatePublisher.schedule()
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            Task { @MainActor in
                guard let self, item != nil, item === self.player.currentItem else { return }
                self.next()
            }
        }
        // A call or an alarm pauses the player by itself; carry on after
        // it when the system says to.
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let info = notification.userInfo
            let type = (info?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap { AVAudioSession.InterruptionType(rawValue: $0) }
            let options = (info?[AVAudioSessionInterruptionOptionKey] as? UInt).map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            guard type == .ended, options.contains(.shouldResume) else { return }
            Task { @MainActor in
                self?.resume()
            }
        }
        // A book's place, every few seconds of listening.
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    /// Plays these songs — those of them that are here — from the one with
    /// `key`, or shuffled with that one first.
    /// False when none of them is here to play.
    @discardableResult
    func play(_ songs: [WatchSong], startingAt key: String? = nil, shuffled: Bool = false) -> Bool {
        let store = WatchDownloadStore.shared
        var playable = songs.filter { store.localURL(for: $0) != nil }
        guard !playable.isEmpty else { return false }
        var start = 0
        if shuffled {
            playable.shuffle()
            if let key, let found = playable.firstIndex(where: { $0.key == key }) {
                playable.swapAt(0, found)
            }
        } else if let key, let found = playable.firstIndex(where: { $0.key == key }) {
            start = found
        }
        leaveBook()
        queue = playable
        index = start
        Task { await startPlayback() }
        return true
    }

    /// Everything on the watch but the books, newest pick first.
    @discardableResult
    func playDownloads(shuffled: Bool) -> Bool {
        let store = WatchDownloadStore.shared
        return play(store.songs(in: store.musicPicks.map(\.key)), shuffled: shuffled)
    }

    // MARK: - Books

    /// Whether a book can play from `time` (book time; nil for where it was
    /// left): the file it falls in is here.
    func canPlayBook(_ pick: WatchPick, from time: TimeInterval? = nil) -> Bool {
        let store = WatchDownloadStore.shared
        let files = store.songs(in: [pick.key])
        let timeline = AudiobookTimeline(partDurations: files.map { $0.duration ?? 0 })
        let start = time ?? WatchBookStore.shared.progress(for: pick.key)?.resumePosition ?? 0
        let part = timeline.location(at: start).part
        return files.indices.contains(part) && store.localURL(for: files[part]) != nil
    }

    /// Plays a book from `time` (book time), or from where it was left. The
    /// book playing already moves there. False when the file it falls in
    /// isn't here yet.
    @discardableResult
    func playBook(_ pick: WatchPick, from time: TimeInterval? = nil) -> Bool {
        if book?.key == pick.key, player.currentItem != nil {
            if let time {
                jump(to: time)
            }
            resume()
            return true
        }
        let store = WatchDownloadStore.shared
        let files = store.songs(in: [pick.key])
        guard !files.isEmpty else { return false }
        let books = WatchBookStore.shared
        let timeline = AudiobookTimeline(partDurations: files.map { $0.duration ?? 0 })
        let start = min(max(time ?? books.progress(for: pick.key)?.resumePosition ?? 0, 0), timeline.duration)
        let location = timeline.location(at: start)
        guard files.indices.contains(location.part), store.localURL(for: files[location.part]) != nil else { return false }
        leaveBook()
        logger.info("Playing \(pick.title, privacy: .public) from \(Int(start)) s (file \(location.part + 1) of \(files.count))")
        // What played before goes now, not once the session is up: until
        // then its clock would read as the book's.
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemObservation = nil
        stopWatchingChapter()
        book = pick
        self.timeline = timeline
        rate = books.rate(for: pick.key)
        queue = files
        index = location.part
        bookPosition = start
        shownChapter = nil
        pendingOffset = location.offset
        pendingPlay = true
        Task { await startPlayback(from: location.offset) }
        return true
    }

    /// Moves the book by `seconds`, back or ahead, across its files.
    func skip(by seconds: TimeInterval) {
        guard book != nil else { return }
        jump(to: currentBookTime + seconds)
    }

    /// Moves the book to `time`, book time: a seek in the file playing,
    /// else the file it falls in, from there. Kept at once: it's a move the
    /// listener made.
    func jump(to time: TimeInterval) {
        guard book != nil, let timeline else { return }
        let target = min(max(time, 0), timeline.duration)
        let location = timeline.location(at: target)
        // A file not on the watch yet: the book stays where it is.
        guard queue.indices.contains(location.part), WatchDownloadStore.shared.localURL(for: queue[location.part]) != nil else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        let play = isPlaying || (pendingOffset != nil && pendingPlay)
        bookPosition = target
        if location.part == index, let item = player.currentItem, pendingOffset == nil {
            player.seek(to: CMTime(seconds: location.offset, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.player.currentItem === item else { return }
                    self.updateNowPlaying()
                }
            }
        } else if player.currentItem == nil {
            // Nothing loaded (the session didn't start): Play loads it here.
            index = location.part
            pendingOffset = location.offset
        } else {
            index = location.part
            loadCurrent(from: location.offset, andPlay: play)
        }
        notePlace(at: target, tellPhoneNow: !play)
    }

    /// Sets a book's speed, kept for that book; at once when it's playing.
    func setRate(_ newRate: Double, for pick: WatchPick) {
        WatchBookStore.shared.setRate(newRate, for: pick.key)
        guard book?.key == pick.key else { return }
        rate = newRate
        player.defaultRate = Float(newRate)
        if isPlaying {
            player.rate = Float(newRate)
        }
        updateNowPlaying()
    }

    /// The chapter playing, when the book has chapters.
    var currentChapter: AudiobookChapter? {
        guard let book else { return nil }
        return WatchBookStore.shared.chapters(for: book.key).chapter(at: bookPosition)
    }

    /// Where the book is now, in book time: where a load is on its way to
    /// until it gets there.
    private var currentBookTime: TimeInterval {
        guard let timeline else { return 0 }
        let offset = pendingOffset ?? player.currentTime().seconds
        return timeline.time(part: index, offset: offset.isFinite ? offset : 0)
    }

    /// Keeps the book's place: where it is now, or `time`.
    private func notePlace(at time: TimeInterval? = nil, tellPhoneNow: Bool = false) {
        guard let book, let timeline else { return }
        let position = time ?? currentBookTime
        bookPosition = position
        let finished = index == queue.count - 1 && position >= timeline.duration - AudiobookProgress.finishedMargin
        WatchBookStore.shared.record(AudiobookProgress(position: position, duration: timeline.duration, isFinished: finished), for: book.key, tellPhoneNow: tellPhoneNow)
    }

    /// Every few seconds while a book plays: its place, and the chapter in
    /// Now Playing.
    private func tick() {
        guard book != nil, isPlaying, pendingOffset == nil else { return }
        notePlace()
        let chapter = currentChapter?.id
        if chapter != shownChapter {
            updateNowPlaying()
        }
    }

    /// The book, before something else takes the player: its place kept
    /// while it plays. A paused book's place was kept as it paused or
    /// moved, and the iPhone may have moved it since: read off the paused
    /// player now, it would take the book back.
    private func leaveBook() {
        guard book != nil else { return }
        if isPlaying {
            notePlace(tellPhoneNow: true)
        }
        dropBook()
    }

    /// Reads how loud the book's file was before the pause, in the
    /// background: as far back as the longest rewind and the pause in the
    /// speech looked for beyond it. A tenth of a second or so of the
    /// watch's time, taken while nothing waits on it.
    private func hearBeforePause() {
        hearing?.cancel()
        heardBeforePause = nil
        guard let paused = bookPause, let url = current.flatMap({ WatchDownloadStore.shared.localURL(for: $0) }) else { return }
        let fileStart = timeline?.start(ofPart: index) ?? 0
        let offset = paused.time - fileStart
        let started = Date.now
        hearing = Task { [weak self] in
            let trace = await Task.detached(priority: .utility) {
                LoudnessTrace.reading(url, from: offset - 20, to: offset)
            }.value
            // Played, moved or left meanwhile: not this pause's any more.
            guard !Task.isCancelled, let self, self.bookPause?.at == paused.at, let trace else { return }
            self.heardBeforePause = (paused.at, trace.shifted(by: fileStart))
            self.logger.notice("smart resume: read \(Int(min(offset, 20))) s before the pause in \(Int(Date.now.timeIntervalSince(started) * 1000)) ms")
        }
    }

    /// Done with a pause: played, left, or the book put away.
    private func forgetPause() {
        hearing?.cancel()
        hearing = nil
        heardBeforePause = nil
        bookPause = nil
    }

    /// Lets go of the book without keeping a place.
    private func dropBook() {
        forgetPause()
        book = nil
        timeline = nil
        rate = 1
        shownChapter = nil
        pendingPlay = false
    }

    /// The end of the book's last file.
    private func finishBook() {
        guard let book, let timeline else { return }
        logger.info("Finished \(book.title, privacy: .public)")
        WatchBookStore.shared.record(AudiobookProgress(position: timeline.duration, duration: timeline.duration, isFinished: true), for: book.key, tellPhoneNow: true)
        dropBook()
        stop()
    }

    /// The picks changed: a book taken off the watch while it's loaded
    /// stops, before its files go, with no place kept for it.
    func picksDidChange() {
        guard let book, !WatchDownloadStore.shared.picks.contains(key: book.key) else { return }
        dropBook()
        stop()
    }

    // MARK: - Transport

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        pendingPlay = false
        player.pause()
    }

    func resume() {
        guard current != nil else { return }
        // The book moved elsewhere since it paused here (the iPhone's place
        // arrived): it plays from there — once that part is on the watch.
        // Until then it doesn't play, rather than take the place back.
        if let book, let place = WatchBookStore.shared.progress(for: book.key),
           abs(place.position - bookPosition) > 15 {
            guard canPlayBook(book, from: place.resumePosition) else {
                logger.notice("\(book.title, privacy: .public): its place moved to a part not on the watch yet")
                WKInterfaceDevice.current().play(.failure)
                return
            }
            jump(to: place.resumePosition)
        } else if let book, let paused = bookPause, player.currentItem != nil, pendingOffset == nil,
                  abs(currentBookTime - paused.time) < 1 {
            // Smart Resume, unless it moved while paused: within the file
            // playing, as on the iPhone, and into a pause in the speech
            // read from the file around there (a few milliseconds).
            let chapters = WatchBookStore.shared.chapters(for: book.key)
            let pause = Date.now.timeIntervalSince(paused.at)
            let fileStart = timeline?.start(ofPart: index) ?? 0
            let plain = SmartResume.resumeTime(from: paused.time, afterPausing: pause, chapters: chapters)
            let heard = heardBeforePause.flatMap { $0.pausedAt == paused.at ? $0.trace : nil }
            let target = SmartResume.resumeTime(from: paused.time, afterPausing: pause, chapters: chapters, heard: heard)
            let landing = heard == nil ? "the plain rewind, the file not read yet" : target == plain ? "no pause in the speech near" : "into a pause in the speech"
            logger.notice("smart resume: back \(paused.time - target, format: .fixed(precision: 2)) s after \(Int(pause)) s paused, \(landing, privacy: .public)")
            jump(to: max(target, fileStart))
        }
        forgetPause()
        if player.currentItem == nil {
            pendingPlay = true
            Task { await startPlayback(from: pendingOffset ?? 0) }
        } else if pendingOffset != nil {
            // On its way to a place: it plays once it's there.
            pendingPlay = true
        } else {
            playAtRate()
        }
    }

    func next() {
        guard index + 1 < queue.count else {
            if book != nil {
                finishBook()
            } else {
                stop()
            }
            return
        }
        index += 1
        loadCurrent()
    }

    /// Back to the start of the song, or to the one before when it's only
    /// just begun.
    func previous() {
        let elapsed = player.currentTime().seconds
        if index == 0 || (elapsed.isFinite && elapsed > 3) {
            player.seek(to: .zero)
            updateNowPlaying()
        } else {
            index -= 1
            loadCurrent()
        }
    }

    private func stop() {
        leaveBook()
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemObservation = nil
        pendingOffset = nil
        stopWatchingChapter()
        queue = []
        index = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        WidgetStatePublisher.schedule()
    }

    private func startPlayback(from offset: TimeInterval = 0) async {
        guard await activateSession() else { return }
        configureCommandsIfNeeded()
        updateCommands()
        // A book paused while the session came up stays paused.
        loadCurrent(from: offset, andPlay: book == nil || pendingPlay)
    }

    /// Long-form audio, so the system routes it to headphones or a speaker
    /// — asking which, when none is connected. False when the person backed
    /// out of the picker or the session couldn't start.
    private func activateSession() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            return try await session.activate(options: [])
        } catch {
            logger.error("Couldn't start the audio session: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Loads the file at `index`, `offset` seconds in, and plays it — or
    /// the next song that's still here, when it was removed from the watch
    /// since the queue was made. A book's file that isn't here stops the
    /// book at its start.
    private func loadCurrent(from offset: TimeInterval = 0, andPlay play: Bool = true) {
        let store = WatchDownloadStore.shared
        itemObservation = nil
        pendingOffset = nil
        while let song = current {
            if let url = store.localURL(for: song) {
                let item = AVPlayerItem(url: url)
                if offset > 0.5 {
                    // Paused until it's there, rather than play the file's
                    // top first.
                    player.pause()
                    player.replaceCurrentItem(with: item)
                    seekWhenReady(item, to: offset, andPlay: play)
                } else {
                    player.replaceCurrentItem(with: item)
                    if book != nil {
                        watchForFailure(of: item)
                    }
                    if play {
                        playAtRate()
                    }
                }
                updateNowPlaying()
                // A skip can keep playing straight through, so the widgets
                // don't hear of the new song from the play state.
                WidgetStatePublisher.schedule()
                return
            }
            // Reached by playing on into it (a jump or a resume goes only to
            // a file that's here), so its start is where listening got to.
            if let book, let timeline {
                logger.notice("\(book.title, privacy: .public): file \(self.index + 1) isn't on the watch yet; stopping there")
                notePlace(at: timeline.start(ofPart: index), tellPhoneNow: true)
                // Let go of before stopping: the player still holds the file
                // before, which would read as a place in this one.
                dropBook()
                stop()
                return
            }
            queue.remove(at: index)
        }
        stop()
    }

    /// Moves a file just loaded to `offset` once it can be (a file not yet
    /// ready has nothing to seek in), then plays it, unless a pause came
    /// meanwhile.
    private func seekWhenReady(_ item: AVPlayerItem, to offset: TimeInterval, andPlay play: Bool) {
        pendingOffset = offset
        pendingPlay = play
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            guard status != .unknown else { return }
            Task { @MainActor in
                guard let self, self.player.currentItem === item, self.itemObservation != nil else { return }
                self.itemObservation = nil
                guard status == .readyToPlay else {
                    self.fileFailed(item)
                    return
                }
                let time = CMTime(seconds: offset, preferredTimescale: 1000)
                self.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    Task { @MainActor in
                        guard self.player.currentItem === item else { return }
                        self.pendingOffset = nil
                        if self.pendingPlay {
                            self.playAtRate()
                        }
                        self.updateNowPlaying()
                    }
                }
            }
        }
    }

    /// A book's file played from its top: watched only in case it won't
    /// open.
    private func watchForFailure(of item: AVPlayerItem) {
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                guard let self, self.player.currentItem === item, self.itemObservation != nil else { return }
                self.itemObservation = nil
                self.fileFailed(item)
            }
        }
    }

    /// A file that won't open (damaged, or a format the watch can't play):
    /// a book stops with its place as it was, since the player's clock
    /// reads the file's top.
    private func fileFailed(_ item: AVPlayerItem) {
        logger.error("Couldn't open the file: \(item.error?.localizedDescription ?? "unknown", privacy: .public)")
        pendingOffset = nil
        guard book != nil else { return }
        dropBook()
        stop()
    }

    private func playAtRate() {
        player.defaultRate = Float(rate)
        player.play()
    }

    private func updateNowPlaying() {
        guard let song = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let elapsed = pendingOffset ?? player.currentTime().seconds
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed.isFinite ? elapsed : 0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: rate,
        ]
        if let album = song.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let duration = song.duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        // A book shows its chapter under the book's title, and the time
        // into the chapter against its length; one without chapters, the
        // file's.
        stopWatchingChapter()
        if let book {
            info[MPMediaItemPropertyAlbumTitle] = book.title
            let chapters = WatchBookStore.shared.chapters(for: book.key)
            let time = currentBookTime
            let chapter = chapters.chapter(at: time)
            shownChapter = chapter?.id
            if let chapter {
                info[MPMediaItemPropertyTitle] = chapter.title
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = min(max(time - chapter.start, 0), chapter.duration)
                info[MPMediaItemPropertyPlaybackDuration] = chapter.duration
                info[MPNowPlayingInfoPropertyChapterNumber] = chapter.id
                info[MPNowPlayingInfoPropertyChapterCount] = chapters.count
                watchForChapter(after: chapter, in: chapters)
            }
        }
        if let image = ArtworkStore.shared.image(for: song.artworkURL) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else if song.artworkURL != nil {
            // Not here yet: fetched, and put in once it is, if the song's
            // still playing.
            Task {
                guard await ArtworkStore.shared.fetch(song.artworkURL) != nil, current?.key == song.key else { return }
                updateNowPlaying()
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Shows the next chapter the moment it starts, when it starts in the
    /// file playing; one in a later file shows as that file loads.
    private func watchForChapter(after chapter: AudiobookChapter, in chapters: [AudiobookChapter]) {
        guard let timeline, let next = chapters.first(where: { $0.start > chapter.start }),
              timeline.location(at: next.start).part == index else { return }
        let offset = next.start - timeline.start(ofPart: index)
        let boundary = NSValue(time: CMTime(seconds: offset + 0.05, preferredTimescale: 1000))
        chapterObserver = player.addBoundaryTimeObserver(forTimes: [boundary], queue: .main) { [weak self] in
            Task { @MainActor in
                self?.updateNowPlaying()
            }
        }
    }

    private func stopWatchingChapter() {
        if let chapterObserver {
            player.removeTimeObserver(chapterObserver)
        }
        chapterObserver = nil
    }

    /// The Now Playing controls, headphone buttons and the system's own
    /// player drive this one.
    private func configureCommandsIfNeeded() {
        guard !commandsConfigured else { return }
        commandsConfigured = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipAhead)]
        center.skipForwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? Self.skipAhead
            Task { @MainActor in self?.skip(by: interval) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipBack)]
        center.skipBackwardCommand.addTarget { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? Self.skipBack
            Task { @MainActor in self?.skip(by: -interval) }
            return .success
        }
        center.changePlaybackRateCommand.supportedPlaybackRates = WatchBookStore.rateChoices.map { NSNumber(value: $0) }
        center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let rate = (event as? MPChangePlaybackRateCommandEvent)?.playbackRate else { return .commandFailed }
            Task { @MainActor in
                guard let self, let book = self.book else { return }
                self.setRate(Double(rate), for: book)
            }
            return .success
        }
    }

    /// A book skips and changes speed; music goes to the next song and
    /// the one before.
    private func updateCommands() {
        let center = MPRemoteCommandCenter.shared()
        let isBook = book != nil
        center.nextTrackCommand.isEnabled = !isBook
        center.previousTrackCommand.isEnabled = !isBook
        center.skipForwardCommand.isEnabled = isBook
        center.skipBackwardCommand.isEnabled = isBook
        center.changePlaybackRateCommand.isEnabled = isBook
    }
}
