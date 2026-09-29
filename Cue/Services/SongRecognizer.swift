import AVFoundation
import Foundation
import MusicKit
import Observation
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

    /// How much of the stream to listen to. Shazam usually needs 3–5
    /// seconds; a little more rides out a DJ talking over an intro.
    private static let sampleSeconds: Double = 10

    /// Listens to the stream `resolve` hands back and names the song on it,
    /// handing a match to `onFound` too. A new call replaces one still
    /// listening.
    func identify(
        stream resolve: @escaping @MainActor () async -> URL?,
        onFound: @escaping @MainActor (RecognizedSong) -> Void = { _ in }
    ) {
        task?.cancel()
        state = .listening
        task = Task { [weak self] in
            let state = await Self.recognize(resolve: resolve)
            guard !Task.isCancelled, let self else { return }
            self.state = state
            if case .found(let song) = state {
                onFound(song)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }

    private static func recognize(resolve: @MainActor () async -> URL?) async -> State {
        guard let url = await resolve() else {
            return .failed("This station's stream can't be reached from this device.")
        }
        do {
            let buffer = try await StreamSampler.sample(url, seconds: sampleSeconds)
            let generator = SHSignatureGenerator()
            try generator.append(buffer, at: nil)
            switch await SHSession().result(from: generator.signature()) {
            case .match(let match):
                guard let item = match.mediaItems.first, let title = item.title else { return .notFound }
                var song = RecognizedSong(
                    title: title,
                    artist: item.artist,
                    artworkURL: item.artworkURL,
                    appleMusicURL: item.appleMusicURL,
                    shazamURL: item.webURL
                )
                song.playable = await catalogSong(id: item.appleMusicID)
                // What Control Center's Shazam does: the song lands in the
                // user's Shazam history, in the Shazam app and Music.
#if !os(visionOS)
                try? await SHLibrary.default.addItems([item])
#endif
                return .found(song)
            case .noMatch:
                return .notFound
            case .error(let error, _):
                return .failed(error.localizedDescription)
            }
        } catch is CancellationError {
            return .idle
        } catch let error as StreamSampler.SampleError {
            return .failed(error.message)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func catalogSong(id: String?) async -> PlayableContent? {
        guard let id else { return nil }
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
        return try? await request.response().items.first?.toPlayable
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

    static func sample(_ url: URL, seconds: Double) async throws -> AVAudioPCMBuffer {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let http = response as? HTTPURLResponse
        if let status = http?.statusCode, !(200..<300).contains(status) {
            throw SampleError(message: "The station's stream answered with an error (\(status)).")
        }
        let fileExtension = try fileExtension(mimeType: response.mimeType, url: url)

        // Enough bytes for `seconds` at the stream's bitrate, when it says;
        // otherwise a ceiling for a high one, with the clock as the real
        // limit. Most servers send a burst on connect, so this is usually
        // quicker than real time.
        let kbps = http?.value(forHTTPHeaderField: "icy-br")
            .flatMap { Int($0.split(separator: ",").first ?? "") } ?? 320
        let target = Int(Double(kbps) * 125 * (seconds + 2))
        let deadline = Date.now.addingTimeInterval(seconds + 6)

        var data = Data()
        data.reserveCapacity(target)
        var chunk = [UInt8]()
        chunk.reserveCapacity(16_384)
        for try await byte in bytes {
            chunk.append(byte)
            if chunk.count == 16_384 {
                data.append(contentsOf: chunk)
                chunk.removeAll(keepingCapacity: true)
                try Task.checkCancellation()
                if data.count >= target || Date.now > deadline { break }
            }
        }
        data.append(contentsOf: chunk)

        let file = FileManager.default.temporaryDirectory
            .appending(path: "shazam-\(UUID().uuidString).\(fileExtension)")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        return try decode(file)
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

    /// Decodes the stream's head into one mono buffer. A cut-off last frame
    /// fails its read, so it reads in slices and keeps what came before.
    private static func decode(_ file: URL) throws -> AVAudioPCMBuffer {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: file)
        } catch {
            throw SampleError(message: "The station's audio couldn't be decoded.")
        }
        let sourceFormat = audioFile.processingFormat
        let slice: AVAudioFrameCount = 8_192
        guard let whole = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(sourceFormat.sampleRate * 20)),
              let piece = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: slice) else {
            throw SampleError(message: "The station's audio couldn't be decoded.")
        }
        while whole.frameLength + slice <= whole.frameCapacity {
            do {
                try audioFile.read(into: piece, frameCount: slice)
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
