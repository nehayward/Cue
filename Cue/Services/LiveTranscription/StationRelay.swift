import AVFoundation
import OSLog

/// Plays a live station through Cue's own audio engine, from one connection,
/// so Live Transcription hears exactly what's heard.
///
/// The station's stream is read and decoded once (`LiveStreamDecoder`). Each
/// chunk goes to `listener` the moment it's decoded, stamped with where it
/// sits on the relay's timeline, and is played `lead` seconds later. That
/// head start is what lets the transcript keep pace: by the time a word is
/// heard, the model has had it for a couple of seconds.
///
/// Every chunk is scheduled with `.dataPlayedBack`, so `heardTime` is where
/// the output actually is — speaker, headphones or AirPlay, latency and all —
/// on the same timeline the listener's stamps use, and a network stall
/// can't pull the two apart.
///
/// Against a second connection, the one thing this is for: stations that
/// insert ads per listener give every connection different ads, and each
/// buffers on its own clock. One connection, one stream.
///
/// MP3 and AAC (ADTS) streams only, as `LiveStreamDecoder` reads; HLS and Ogg
/// fail at `start`.
final class StationRelay: @unchecked Sendable {
    typealias Listener = @Sendable (AVAudioPCMBuffer, CMTime) -> Void

    /// How far playback runs behind decoding.
    static let lead: TimeInterval = 2

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let lock = NSLock()

    /// The format the node is connected in — the stream's own, set by the
    /// first chunk.
    private var format: AVAudioFormat?
    /// Where the next chunk goes on the timeline, in frames at the stream's
    /// rate. Carries on across a stop and start, so the timeline only ever
    /// moves forward.
    private var scheduledEnd: AVAudioFramePosition = 0
    /// Where the timeline was when the current run began, for the lead.
    private var runStart: AVAudioFramePosition = 0
    /// The end of the last chunk the output has actually played, and when
    /// it got there.
    private var heardEnd: AVAudioFramePosition?
    private var heardAt: TimeInterval = 0
    /// Bumped by every stop, so a stopped run's late callbacks change
    /// nothing — the node calls them all back when it stops.
    private var generation = 0
    private var isStarted = false
    private var currentListener: Listener?
    private var decodeTask: Task<Void, Never>?
    private var configurationObserver: NSObjectProtocol?

    /// Who hears each chunk as it's decoded. Can be swapped while the relay
    /// plays — a new transcription run on the same station — without
    /// reopening the stream.
    var listener: Listener? {
        get { lock.withLock { currentListener } }
        set { lock.withLock { currentListener = newValue } }
    }

    /// The output level, 0...1. The listener hears the station at full
    /// level whatever this is.
    var volume: Float {
        get { node.volume }
        set { node.volume = newValue }
    }

    init() {
        engine.attach(node)
        // A route change — AirPlay picked, headphones pulled — stops the
        // engine; pick up where it was.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.restartAfterConfigurationChange()
        }
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        decodeTask?.cancel()
        node.stop()
        engine.stop()
    }

    /// Whether the relay is playing to the output.
    var isPlaying: Bool {
        lock.withLock { isStarted } && engine.isRunning && node.isPlaying
    }

    /// Where the output is on the relay's timeline, in seconds. A chunk
    /// reports in once it's been heard to its end, and a chunk can run a
    /// quarter of a second, so the time since then is added — capped, so a
    /// stall doesn't run it on ahead of the audio. Nil before anything has
    /// been heard.
    var heardTime: TimeInterval? {
        lock.withLock {
            guard let heardEnd, let format else { return nil }
            let since = isStarted ? min(ProcessInfo.processInfo.systemUptime - heardAt, Self.maxInterpolation) : 0
            return Double(heardEnd) / format.sampleRate + max(since, 0)
        }
    }

    private static let maxInterpolation: TimeInterval = 0.3

    /// Opens `url` and plays it, `lead` seconds behind `listener`.
    /// `onReady` is called, on the main actor, once the lead is buffered and
    /// playback is about to begin — the moment to silence anything playing
    /// the station before; returning false calls it off and stops the relay.
    /// `onEnd` is called, on the main actor, if the
    /// stream can't be read or stops.
    func start(
        url: URL,
        listener: @escaping Listener,
        onReady: @escaping @MainActor () -> Bool,
        onEnd: @escaping @MainActor (Error?) -> Void
    ) {
        stop()
        let generation = lock.withLock {
            runStart = scheduledEnd
            currentListener = listener
            return self.generation
        }
        decodeTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await LiveStreamDecoder.run(url) { buffer in
                    self?.receive(buffer, generation: generation, onReady: onReady)
                }
                guard !Task.isCancelled else { return }
                await onEnd(nil)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                Logger.liveTranscription.error("Relay failed: \(error.localizedDescription, privacy: .public)")
                await onEnd(error)
            }
        }
    }

    /// Stops reading and playing. What's buffered is dropped — it's live
    /// radio, and a start opens the station again where it is now.
    func stop() {
        decodeTask?.cancel()
        decodeTask = nil
        lock.withLock {
            generation += 1
            isStarted = false
        }
        node.stop()
        engine.pause()
    }

    // MARK: - Decoding thread

    private func receive(
        _ buffer: AVAudioPCMBuffer,
        generation: Int,
        onReady: @escaping @MainActor () -> Bool
    ) {
        guard prepare(for: buffer.format) else { return }

        let (start, end, beginsPlayback) = lock.withLock { () -> (AVAudioFramePosition, AVAudioFramePosition, Bool) in
            let start = scheduledEnd
            scheduledEnd += AVAudioFramePosition(buffer.frameLength)
            let buffered = Double(scheduledEnd - runStart) / buffer.format.sampleRate
            let begins = !isStarted && generation == self.generation && buffered >= Self.lead
            if begins { isStarted = true }
            return (start, scheduledEnd, begins)
        }
        guard let listener = lock.withLock({ generation == self.generation ? currentListener : nil }) else { return }

        listener(buffer, CMTime(value: start, timescale: CMTimeScale(buffer.format.sampleRate)))

        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.played(upTo: end, generation: generation)
        }

        if beginsPlayback {
            Task { @MainActor [weak self] in
                guard let self, self.lock.withLock({ generation == self.generation }) else { return }
                if onReady() {
                    self.beginPlayback()
                } else {
                    self.stop()
                }
            }
        }
    }

    /// Connects the node in the stream's format on the first chunk. A chunk
    /// in another format — a stream that changed mid-flight — is dropped.
    private func prepare(for format: AVAudioFormat) -> Bool {
        let connected = lock.withLock { self.format }
        if let connected {
            return connected == format
        }
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        lock.withLock { self.format = format }
        return true
    }

    private func played(upTo end: AVAudioFramePosition, generation: Int) {
        lock.withLock {
            guard generation == self.generation else { return }
            heardEnd = max(heardEnd ?? 0, end)
            heardAt = ProcessInfo.processInfo.systemUptime
        }
    }

    @MainActor
    private func beginPlayback() {
        do {
            if !engine.isRunning {
                try engine.start()
            }
            node.play()
        } catch {
            Logger.liveTranscription.error("Relay couldn't start the engine: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func restartAfterConfigurationChange() {
        guard lock.withLock({ isStarted }) else { return }
        Task { @MainActor [weak self] in
            self?.beginPlayback()
        }
    }
}
