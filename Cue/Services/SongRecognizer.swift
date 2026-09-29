import AVFoundation
import Foundation
import MusicKit
import Observation
import os
import ShazamKit
import SonosKit

/// A song Shazam named, and where it can be found.
struct RecognizedSong: Equatable {
    let title: String
    let artist: String?
    let artworkURL: URL?
    let appleMusicURL: URL?
    let shazamURL: URL?
    /// The catalog song, when Apple Music has it — the row that plays,
    /// queues and adds to a playlist like any search result.
    var playable: PlayableContent?
}

/// Names the song on a radio station with ShazamKit.
///
/// It listens to the station's stream, not the room: a few seconds of the
/// same URL the player is playing are fetched and decoded here, and their
/// signature matched against Shazam's catalog. That needs no microphone,
/// works through headphones, and works the same for a station on this
/// device and one on a Sonos group — the speaker plays a URL this device
/// can open too. HLS and Ogg streams can't be sampled this way.
///
/// The Shazam catalog needs the ShazamKit App Service turned on for the
/// app's identifier in the developer portal.
@MainActor
@Observable
final class SongRecognizer {
    static let shared = SongRecognizer()

    enum State: Equatable {
        case idle
        case listening
        case found(RecognizedSong)
        case notFound
        case failed(String)
    }

    private(set) var state: State = .idle
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    /// The song last named on each stream, and until when it's still on:
    /// a second tap during the same song answers at once instead of
    /// listening again.
    @ObservationIgnored private var known: [String: (song: RecognizedSong, until: Date)] = [:]

    /// Where Shazam gets a go, in seconds of stream. Most songs match on
    /// the first; a quiet intro or a DJ over it gets the longer ones.
    /// Shazam turns a signature much past the last away
    /// (`SHError.signatureDurationInvalid`, 201).
    private static let checkpoints: [Double] = [3, 5, 8]

    /// How long a song is taken to stay on when its length isn't known.
    private static let assumedRemaining: TimeInterval = 45

    /// How long a listen may take in all — reaching the stream, sampling
    /// it and hearing back from Shazam — before it gives up. A stalled
    /// stream otherwise left the logo pulsing for good.
    private static let timeout: Duration = .seconds(25)

    /// Listens to the stream `resolve` hands back and names the song on it,
    /// handing the outcome to `onFinish`. A new call replaces one still
    /// listening, whose `onFinish` then never runs.
    ///
    /// `stream` names the station, so a song already named on it answers
    /// straight away while it's still playing.
    func identify(
        stream key: String?,
        url resolve: @escaping @MainActor () async -> URL?,
        onFinish: @escaping @MainActor (State) -> Void = { _ in }
    ) {
        task?.cancel()
        timeoutTask?.cancel()
        known = known.filter { $0.value.until > .now }
        if let key, let hit = known[key] {
            task = nil
            timeoutTask = nil
            state = .found(hit.song)
            onFinish(state)
            return
        }
        state = .listening
        let listen = Task { [weak self] in
            let (state, until) = await Self.recognize(resolve: resolve)
            guard !Task.isCancelled, let self else { return }
            self.timeoutTask?.cancel()
            self.timeoutTask = nil
            if let key, case .found(let song) = state {
                self.known[key] = (song, until ?? .now.addingTimeInterval(Self.assumedRemaining))
            }
            self.state = state
            onFinish(state)
        }
        task = listen
        // Gives up without waiting on the listen to notice it was
        // cancelled — a stalled read or Shazam call may not for a while.
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled, let self, self.task == listen else { return }
            listen.cancel()
            self.task = nil
            self.timeoutTask = nil
            let state = State.failed("Shazam took too long to listen. Try again in a moment.")
            self.state = state
            onFinish(state)
        }
    }

    var isListening: Bool { state == .listening }

    func cancel() {
        task?.cancel()
        task = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        state = .idle
    }

    /// Names the song, and says until when it plays when Apple Music knows
    /// its length.
    private static func recognize(resolve: @MainActor () async -> URL?) async -> (State, Date?) {
        guard let url = await resolve() else {
            return (.failed("This station's stream can't be reached from this device."), nil)
        }
        do {
            // Asks at each checkpoint as the stream comes in, rather than
            // collecting all of it first.
            let match = try await StreamSampler.listen(url, checkpoints: checkpoints) { buffer -> SHMatch? in
                let generator = SHSignatureGenerator()
                try generator.append(buffer, at: nil)
                switch await SHSession().result(from: generator.signature()) {
                case .match(let match):
                    return match
                case .noMatch:
                    return nil
                case .error(let error, _):
                    throw ShazamFailure(underlying: error)
                }
            }
            guard let match, let item = match.mediaItems.first, let title = item.title else {
                return (.notFound, nil)
            }
            let heardAt = Date.now
            var song = RecognizedSong(
                title: title,
                artist: item.artist,
                artworkURL: item.artworkURL,
                appleMusicURL: item.appleMusicURL,
                shazamURL: item.webURL
            )
            let catalog = await catalogSong(id: item.appleMusicID)
            song.playable = catalog?.toPlayable
            // What Control Center's Shazam does: the song lands in the
            // user's Shazam history, in the Shazam app and Music. Off to
            // the side, so the answer doesn't wait on it.
#if !os(visionOS)
            Task.detached { try? await SHLibrary.default.addItems([item]) }
#endif
            // Held a little short of the song's end, so the next one isn't
            // answered with this one.
            let until = catalog?.duration.map {
                heardAt.addingTimeInterval($0 - item.predictedCurrentMatchOffset - 15)
            }
            return (.found(song), until)
        } catch is CancellationError {
            return (.idle, nil)
        } catch let error as StreamSampler.SampleError {
            return (.failed(error.message), nil)
        } catch let failure as ShazamFailure {
            // Shazam's own errors read as "The operation couldn't be
            // completed (com.apple.ShazamCore error 102)" — no use to
            // anyone. The detail goes to the log instead.
            logger.error("Shazam match failed: \(String(describing: failure.underlying), privacy: .public)")
            return (.failed("Shazam couldn't be reached. Try again in a moment."), nil)
        } catch {
            return (.failed(error.localizedDescription), nil)
        }
    }

    private struct ShazamFailure: Error {
        let underlying: Error
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Cue", category: "SongRecognizer")

    private static func catalogSong(id: String?) async -> Song? {
        guard let id else { return nil }
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
        return try? await request.response().items.first
    }
}

/// Reads a few seconds of a live stream into PCM that ShazamKit takes.
enum StreamSampler {
    struct SampleError: Error {
        let message: String
    }

    /// Shazam's signatures take PCM at 16, 32, 44.1 or 48 kHz; one mono
    /// format sidesteps the low-bitrate streams at 22.05 or 24 kHz.
    private static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false)!

    /// Reads the stream and hands `attempt` its first few seconds as each
    /// checkpoint's worth comes in, until it answers with something. Nil
    /// when every checkpoint went by without one.
    ///
    /// How far along the stream is is read off the audio itself, not
    /// guessed from a bitrate — a guess too high had it wait on bytes a
    /// 128 kbps station takes half a minute to send.
    static func listen<Answer>(
        _ url: URL,
        checkpoints: [Double],
        attempt: (AVAudioPCMBuffer) async throws -> Answer?
    ) async throws -> Answer? {
        guard let longest = checkpoints.max() else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let http = response as? HTTPURLResponse
        if let status = http?.statusCode, !(200..<300).contains(status) {
            throw SampleError(message: "The station's stream answered with an error (\(status)).")
        }
        let fileExtension = try fileExtension(mimeType: response.mimeType, url: url)
        let file = FileManager.default.temporaryDirectory
            .appending(path: "shazam-\(UUID().uuidString).\(fileExtension)")
        defer { try? FileManager.default.removeItem(at: file) }

        // Most servers send a burst on connect, so the first checkpoints
        // usually come quicker than real time.
        let deadline = Date.now.addingTimeInterval(longest + 6)
        var remaining = checkpoints.sorted()
        var data = Data()
        var chunk = [UInt8]()
        chunk.reserveCapacity(8_192)

        /// Tries every checkpoint the audio so far reaches — or, at the
        /// end, once more with all there is.
        func attemptReached(final: Bool) async throws -> Answer? {
            data.append(contentsOf: chunk)
            chunk.removeAll(keepingCapacity: true)
            try data.write(to: file)
            let seconds = decodedSeconds(file)
            // Under three seconds is too little for Shazam to go on.
            guard seconds >= 3 else { return nil }
            if final {
                guard let last = remaining.last else { return nil }
                remaining.removeAll()
                return try await attempt(decode(file, seconds: min(last, seconds)))
            }
            while let next = remaining.first, seconds >= next {
                remaining.removeFirst()
                if let answer = try await attempt(decode(file, seconds: next)) { return answer }
            }
            return nil
        }

        for try await byte in bytes {
            chunk.append(byte)
            guard chunk.count == 8_192 else { continue }
            try Task.checkCancellation()
            if let answer = try await attemptReached(final: false) { return answer }
            if remaining.isEmpty { return nil }
            if Date.now > deadline { break }
        }
        // The stream ended or dried up: one last go with whatever came.
        if let answer = try await attemptReached(final: true) { return answer }
        if decodedSeconds(file) < 3 {
            throw SampleError(message: "Not enough of the station came through to listen to.")
        }
        return nil
    }

    /// How many seconds of audio the file holds so far, 0 when it can't
    /// be read yet.
    private static func decodedSeconds(_ file: URL) -> Double {
        guard let audioFile = try? AVAudioFile(forReading: file) else { return 0 }
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }

    private static func fileExtension(mimeType: String?, url: URL) throws -> String {
        let mime = mimeType?.lowercased() ?? ""
        let pathExtension = url.pathExtension.lowercased()
        if mime.contains("mpegurl") || pathExtension == "m3u8" {
            throw SampleError(message: "This station streams in HLS, which can't be sampled for recognition yet.")
        }
        if mime.contains("ogg") || mime.contains("opus") || ["ogg", "oga", "opus"].contains(pathExtension) {
            throw SampleError(message: "This station streams in Ogg, which can't be sampled for recognition.")
        }
        if mime.contains("aac") || pathExtension == "aac" {
            return "aac"
        }
        return "mp3"
    }

    /// Decodes the stream's head into one mono buffer of at most `seconds`
    /// — a server's burst on connect can hand over far more, and too long a
    /// signature is refused outright. A cut-off last frame fails its read,
    /// so it reads in slices and keeps what came before.
    private static func decode(_ file: URL, seconds: Double) throws -> AVAudioPCMBuffer {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: file)
        } catch {
            throw SampleError(message: "The station's audio couldn't be decoded.")
        }
        let sourceFormat = audioFile.processingFormat
        let slice: AVAudioFrameCount = 8_192
        guard let whole = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(sourceFormat.sampleRate * seconds)),
              let piece = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: slice) else {
            throw SampleError(message: "The station's audio couldn't be decoded.")
        }
        while whole.frameLength < whole.frameCapacity {
            do {
                try audioFile.read(into: piece, frameCount: min(slice, whole.frameCapacity - whole.frameLength))
            } catch {
                break
            }
            guard piece.frameLength > 0 else { break }
            append(piece, to: whole)
        }
        // Under three seconds is too little for Shazam to go on.
        guard Double(whole.frameLength) / sourceFormat.sampleRate >= 3 else {
            throw SampleError(message: "Not enough of the station came through to listen to.")
        }
        return try convert(whole)
    }

    private static func append(_ piece: AVAudioPCMBuffer, to whole: AVAudioPCMBuffer) {
        guard let from = piece.floatChannelData, let to = whole.floatChannelData else { return }
        let offset = Int(whole.frameLength)
        let count = Int(piece.frameLength)
        for channel in 0..<Int(piece.format.channelCount) {
            (to[channel] + offset).update(from: from[channel], count: count)
        }
        whole.frameLength += piece.frameLength
    }

    private static func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            throw SampleError(message: "The station's audio couldn't be decoded.")
        }
        converter.downmix = true
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 4_096
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw SampleError(message: "The station's audio couldn't be decoded.")
        }
        var handedOver = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if handedOver {
                status.pointee = .endOfStream
                return nil
            }
            handedOver = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        return output
    }
}
