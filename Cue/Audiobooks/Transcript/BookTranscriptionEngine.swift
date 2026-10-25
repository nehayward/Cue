import AVFoundation
import CoreMedia
import OSLog
import Speech

/// A stretch of a book file's audio and where in the file it starts.
struct BookAudioChunk: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let start: TimeInterval
}

/// How far a file read ahead may get: not more than a little past what the
/// transcriber has got to (it reads far faster than it transcribes, and
/// what it hasn't got to would wait in memory), nor too far past where the
/// listener is. Written on the main actor, read by the reader's task.
///
/// "Got to" is the transcriber's running progress, its best guesses
/// included, not only what it's finished: it finishes a stretch only once
/// it's heard what follows, so pacing on finished stretches alone left the
/// reader waiting for a transcriber waiting for it.
final class BookTranscriptPace: @unchecked Sendable {
    /// How far ahead of the listener a file is read.
    static let lookahead: TimeInterval = 5 * 60
    /// How far past what's transcribed the reader may get.
    static let backlog: TimeInterval = 45

    private let lock = NSLock()
    private var _playhead: TimeInterval = 0
    private var _heardThrough: TimeInterval = 0
    private var _fed: TimeInterval = 0
    private var _progressAt = Date.now

    var playhead: TimeInterval {
        get { lock.withLock { _playhead } }
        set { lock.withLock { _playhead = newValue } }
    }
    var heardThrough: TimeInterval {
        get { lock.withLock { _heardThrough } }
        set {
            lock.withLock {
                if newValue > _heardThrough { _progressAt = .now }
                _heardThrough = max(_heardThrough, newValue)
            }
        }
    }
    var fed: TimeInterval {
        get { lock.withLock { _fed } }
        set { lock.withLock { _fed = newValue } }
    }

    init(start: TimeInterval) {
        _heardThrough = start
        _fed = start
    }

    /// Whether the reader should wait before reading on from `fed`. A
    /// transcriber that's made no progress for a few seconds gets more to
    /// go on, up to a few minutes' backlog, rather than a wait on both sides.
    var shouldWait: Bool {
        lock.withLock {
            guard _fed <= _playhead + Self.lookahead else { return true }
            let backlog = _fed - _heardThrough
            if backlog <= Self.backlog { return false }
            return backlog > Self.backlog * 6 || Date.now.timeIntervalSince(_progressAt) < 4
        }
    }
}

/// The on-device transcriber behind a book's transcript: Apple's
/// `SpeechAnalyzer` with a `SpeechTranscriber` asked for each word's time,
/// fed a book file's audio — read from the file ahead of the listener when
/// it's downloaded, or heard as it plays when it's streamed. Nothing leaves
/// the device. A language's model downloads the first time it's needed.
@available(iOS 26.0, visionOS 26.0, *)
enum BookTranscriptionEngine {
    enum Status: Equatable {
        /// The language's model is on its way down, 0...1.
        case downloading(Double)
        case transcribing
    }

    /// Transcribes `audio`, on file time from its first chunk, until the
    /// task is cancelled or the audio ends. `onLines` gets each finished
    /// stretch as lines, with the file time it runs through; `onProgress`
    /// how far it's got, guesses included; `onVolatile`, with `live`, the
    /// best guess at what's being said now.
    static func run(
        locale: Locale,
        audio: AsyncStream<BookAudioChunk>,
        live: Bool,
        onStatus: @escaping @MainActor (Status) -> Void,
        onLines: @escaping @MainActor ([BookTranscript.Line], TimeInterval) -> Void,
        onProgress: @escaping @MainActor (TimeInterval) -> Void = { _ in },
        onVolatile: @escaping @MainActor (String?) -> Void
    ) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionEngine.EngineError.unsupportedLocale
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            await onStatus(.downloading(0))
            let progress = request.progress
            let reporter = Task { @MainActor in
                while !Task.isCancelled {
                    onStatus(.downloading(progress.fractionCompleted))
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            defer { reporter.cancel() }
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionEngine.EngineError.noAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        // The model loaded before any audio: fed a burst while it was still
        // loading, the first seconds of a run came out as noise.
        try await analyzer.prepareToAnalyze(in: format)
        let (inputs, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: inputs)
        await onStatus(.transcribing)

        // The analyzer's timeline starts at zero with the first chunk; the
        // origin is where that is in the file.
        let origin = OriginBox()
        let pump = Task.detached(priority: .userInitiated) {
            let converter = BufferConverter(to: format)
            // In the analyzer's own samples, so a chunk can't be rounded to
            // start a hair before the last one ended, which it turns away
            // ("timestamp overlaps or precedes prior audio input").
            let rate = format.sampleRate
            var lastEnd: Int64 = 0
            for await chunk in audio {
                guard let converted = converter.convert(chunk.buffer) else { continue }
                let base = origin.set(chunk.start)
                let at = max(Int64(((chunk.start - base) * rate).rounded()), lastEnd)
                lastEnd = at + Int64(converted.frameLength)
                inputBuilder.yield(AnalyzerInput(buffer: converted, bufferStartTime: CMTime(value: at, timescale: CMTimeScale(rate))))
            }
            inputBuilder.finish()
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }

        try await withTaskCancellationHandler {
            do {
                for try await result in transcriber.results {
                    let base = origin.value
                    if result.range.end.isNumeric {
                        await onProgress(base + result.range.end.seconds)
                    }
                    if result.isFinal {
                        let words = result.text.runs.map { run in
                            BookTranscript.Word(
                                text: String(result.text[run.range].characters),
                                start: run.audioTimeRange.flatMap { $0.start.isNumeric ? base + $0.start.seconds : nil }
                            )
                        }
                        let start = base + (result.range.start.isNumeric ? result.range.start.seconds : 0)
                        let end = base + (result.range.end.isNumeric ? result.range.end.seconds : 0)
                        let lines = BookTranscript.lines(from: words, fallbackStart: start, end: max(end, start))
                        await onLines(lines, max(end, start))
                        if live { await onVolatile(nil) }
                    } else if live {
                        let text = String(result.text.characters).trimmingCharacters(in: .whitespaces)
                        await onVolatile(text.isEmpty ? nil : text)
                    }
                }
            } catch where !Task.isCancelled {
                throw error
            } catch {}
        } onCancel: {
            pump.cancel()
            inputBuilder.finish()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    /// A downloaded file's audio from `start`, read as `pace` allows, to
    /// the file's end. Nil when the file can't be opened.
    static func read(_ url: URL, from start: TimeInterval, pace: BookTranscriptPace) -> AsyncStream<BookAudioChunk>? {
        guard let file = try? AVAudioFile(forReading: url) else {
            Logger.bookTranscript.error("can't open \(url.lastPathComponent, privacy: .public) to read")
            return nil
        }
        let format = file.processingFormat
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * 2)
        return AsyncStream { continuation in
            let reader = Task.detached(priority: .utility) {
                file.framePosition = AVAudioFramePosition(max(start, 0) * rate)
                var time = Double(file.framePosition) / rate
                pace.fed = time
                while !Task.isCancelled {
                    if pace.shouldWait {
                        try? await Task.sleep(for: .milliseconds(400))
                        continue
                    }
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { break }
                    do { try file.read(into: buffer, frameCount: frames) } catch { break }
                    guard buffer.frameLength > 0 else { break }
                    continuation.yield(BookAudioChunk(buffer: buffer, start: time))
                    time += Double(buffer.frameLength) / rate
                    pace.fed = time
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
    }
}

extension BookTranscriptionEngine {
    /// How much is asked of the server at a time: about this many seconds.
    private static let remoteStep: TimeInterval = 20

    /// A book's MP3 on the server, read ahead from `start` as `pace` allows
    /// with nothing playing: fetched about 20 seconds at a time (a range
    /// request, as the player's own are) and decoded here, the way radio's
    /// Live Transcription decodes a station (`StreamParser`). The place in
    /// the file is reckoned from its length and `duration`, as a player
    /// seeking a constant-bitrate MP3 does. Nil for a file that isn't MP3 —
    /// an M4B keeps its index at either end, so a piece of one can't be
    /// read alone — or a server that won't send ranges.
    static func read(remote url: URL, duration: TimeInterval, from start: TimeInterval, pace: BookTranscriptPace) async -> AsyncStream<BookAudioChunk>? {
        guard duration > 0 else { return nil }
        var request = URLRequest(url: url)
        request.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
        request.timeoutInterval = 20
        guard let (head, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 206,
              let total = Self.totalLength(http), total > 0 else {
            Logger.bookTranscript.notice("server won't send a book file in pieces")
            return nil
        }
        guard let audioStart = Self.mp3AudioStart(head) else {
            Logger.bookTranscript.notice("book file isn't MP3; heard as it plays instead")
            return nil
        }
        let bytesPerSecond = Double(total - audioStart) / duration
        let step = max(Int64(bytesPerSecond * remoteStep), 64 * 1024)
        let clock = DecodeClock(time: max(start, 0))
        return AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                guard let parser = try? StreamParser(fileType: kAudioFileMP3Type, onBuffer: { buffer in
                    let at = clock.advance(by: Double(buffer.frameLength) / buffer.format.sampleRate)
                    continuation.yield(BookAudioChunk(buffer: buffer, start: at))
                    pace.fed = clock.time
                }) else {
                    continuation.finish()
                    return
                }
                var offset = audioStart + Int64(max(start, 0) * bytesPerSecond)
                pace.fed = start
                while !Task.isCancelled, offset < total {
                    if pace.shouldWait {
                        try? await Task.sleep(for: .milliseconds(400))
                        continue
                    }
                    var piece = URLRequest(url: url)
                    piece.setValue("bytes=\(offset)-\(min(offset + step, total) - 1)", forHTTPHeaderField: "Range")
                    piece.timeoutInterval = 30
                    guard let (data, _) = try? await URLSession.shared.data(for: piece), !data.isEmpty else {
                        Logger.bookTranscript.notice("a piece of the book file didn't come; stopping here")
                        break
                    }
                    do { try parser.parse([UInt8](data)) } catch { break }
                    offset += Int64(data.count)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The file's length, from a range answer's `Content-Range`.
    private static func totalLength(_ response: HTTPURLResponse) -> Int64? {
        guard let range = response.value(forHTTPHeaderField: "Content-Range"),
              let total = range.split(separator: "/").last else { return nil }
        return Int64(total)
    }

    /// Where an MP3's audio starts, past its ID3 tag; nil when the bytes
    /// aren't an MP3's.
    private static func mp3AudioStart(_ head: Data) -> Int64? {
        let bytes = [UInt8](head.prefix(16))
        guard bytes.count >= 10 else { return nil }
        var start: Int64 = 0
        if bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 {
            // ID3v2: a synchsafe size after a 10-byte header.
            let size = (Int64(bytes[6] & 0x7F) << 21) | (Int64(bytes[7] & 0x7F) << 14) | (Int64(bytes[8] & 0x7F) << 7) | Int64(bytes[9] & 0x7F)
            start = 10 + size + (bytes[5] & 0x10 != 0 ? 10 : 0)
        }
        // An MP4 (M4B, M4A) names its type four bytes in.
        if bytes.count >= 8, bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 { return nil }
        // Past a tag the frames may not be in the first bytes read; with no
        // tag, the first must be a frame's sync word.
        if start == 0, !(bytes[0] == 0xFF && bytes[1] & 0xE0 == 0xE0) { return nil }
        return start
    }
}

/// The time decoded audio has reached, kept by the parser's callback.
private final class DecodeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _time: TimeInterval

    init(time: TimeInterval) { _time = time }

    var time: TimeInterval { lock.withLock { _time } }

    /// Moves on by `seconds`, returning where it was.
    func advance(by seconds: TimeInterval) -> TimeInterval {
        lock.withLock {
            let at = _time
            _time += seconds
            return at
        }
    }
}

/// Where the analyzer's zero is in the file: the first chunk's time.
private final class OriginBox: @unchecked Sendable {
    private let lock = NSLock()
    private var origin: TimeInterval?

    /// The origin, set to `time` if there's none yet.
    func set(_ time: TimeInterval) -> TimeInterval {
        lock.withLock {
            if let origin { return origin }
            origin = time
            return time
        }
    }

    var value: TimeInterval { lock.withLock { origin ?? 0 } }
}

extension Logger {
    static let bookTranscript = Logger(subsystem: "dance.cue", category: "bookTranscript")
}
