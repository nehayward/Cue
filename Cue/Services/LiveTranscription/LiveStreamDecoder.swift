import AudioToolbox
import AVFoundation
import DanceLogger

/// Plays a live radio stream into PCM, without a speaker: the station's
/// bytes are read straight off the network, split into MP3 or AAC frames by
/// `AudioFileStream`, and decoded by `AVAudioConverter` as they arrive.
///
/// This is how Live Transcription hears a station — the same URL the player
/// or the speaker is playing, opened a second time here. `AVPlayer` can't be
/// listened in on for this: an audio tap needs an asset track, which a live
/// Icecast or Shoutcast stream never has.
///
/// MP3 and AAC (ADTS) streams only. HLS and Ogg are turned away up front.
enum LiveStreamDecoder {
    struct DecodeError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Decodes `url` until the task is cancelled or the stream ends, handing
    /// each decoded chunk to `onBuffer` at the stream's own rate and channel
    /// count.
    static func run(_ url: URL, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw DecodeError(message: "The station's stream answered with an error (\(status)).")
        }
        let parser = try StreamParser(fileType: fileType(mimeType: response.mimeType, url: url), onBuffer: onBuffer)
        DanceLog.liveTranscription.info("Decoding \(url.absoluteString, privacy: .public) (\(response.mimeType ?? "no type", privacy: .public))")

        var chunk = [UInt8]()
        chunk.reserveCapacity(chunkSize)
        for try await byte in bytes {
            chunk.append(byte)
            if chunk.count == chunkSize {
                try Task.checkCancellation()
                try parser.parse(chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty {
            try parser.parse(chunk)
        }
    }

    /// About a quarter second of a 128 kbps stream: small enough that words
    /// reach the model promptly, big enough not to thrash the parser.
    private static let chunkSize = 4096

    private static func fileType(mimeType: String?, url: URL) throws -> AudioFileTypeID {
        let mime = mimeType?.lowercased() ?? ""
        let pathExtension = url.pathExtension.lowercased()
        if mime.contains("mpegurl") || pathExtension == "m3u8" {
            throw DecodeError(message: "This station streams in HLS, which can't be transcribed yet.")
        }
        if mime.contains("ogg") || mime.contains("opus") || ["ogg", "oga", "opus"].contains(pathExtension) {
            throw DecodeError(message: "This station streams in Ogg, which can't be transcribed.")
        }
        if mime.contains("aac") || mime.contains("mp4a") || ["aac", "m4a"].contains(pathExtension) {
            return kAudioFileAAC_ADTSType
        }
        return kAudioFileMP3Type
    }
}

/// One stream's `AudioFileStream` and the converter behind it. The parser's
/// C callbacks come back through `clientData` to this object, synchronously
/// inside `parse`, on the caller's thread.
private final class StreamParser {
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    private var stream: AudioFileStreamID?
    private var compressedFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var maximumPacketSize: UInt32 = 0
    /// A failure inside a callback, raised from `parse` once it returns.
    private var failure: Error?

    init(fileType: AudioFileTypeID, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        self.onBuffer = onBuffer
        let status = AudioFileStreamOpen(
            Unmanaged.passUnretained(self).toOpaque(),
            { clientData, stream, property, _ in
                Unmanaged<StreamParser>.fromOpaque(clientData).takeUnretainedValue()
                    .propertyChanged(property, on: stream)
            },
            { clientData, byteCount, packetCount, data, descriptions in
                Unmanaged<StreamParser>.fromOpaque(clientData).takeUnretainedValue()
                    .received(byteCount: byteCount, packetCount: packetCount, data: data, descriptions: descriptions)
            },
            fileType,
            &stream
        )
        guard status == noErr else {
            throw LiveStreamDecoder.DecodeError(message: "Couldn't read this station's stream (\(status)).")
        }
    }

    deinit {
        if let stream { AudioFileStreamClose(stream) }
    }

    func parse(_ bytes: [UInt8]) throws {
        guard let stream else { return }
        let status = bytes.withUnsafeBytes { buffer in
            AudioFileStreamParseBytes(stream, UInt32(buffer.count), buffer.baseAddress, [])
        }
        if let failure {
            throw failure
        }
        // A bad frame mid-stream is skipped over by the parser; only a
        // stream it can't make sense of from the start is fatal.
        if status != noErr, converter == nil {
            throw LiveStreamDecoder.DecodeError(message: "This station's stream isn't MP3 or AAC (\(status)).")
        }
    }

    /// Once the parser knows the stream's format, sets up the decoder.
    private func propertyChanged(_ property: AudioFileStreamPropertyID, on stream: AudioFileStreamID) {
        guard property == kAudioFileStreamProperty_ReadyToProducePackets else { return }

        var description = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_DataFormat, &size, &description) == noErr,
              let compressed = AVAudioFormat(streamDescription: &description),
              let pcm = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: description.mSampleRate,
                  channels: max(description.mChannelsPerFrame, 1),
                  interleaved: false
              ),
              let converter = AVAudioConverter(from: compressed, to: pcm) else {
            failure = LiveStreamDecoder.DecodeError(message: "Couldn't decode this station's audio.")
            return
        }

        var cookieSize: UInt32 = 0
        var writable: DarwinBoolean = false
        if AudioFileStreamGetPropertyInfo(stream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable) == noErr, cookieSize > 0 {
            var cookie = Data(count: Int(cookieSize))
            let read = cookie.withUnsafeMutableBytes { buffer in
                AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, buffer.baseAddress!)
            }
            if read == noErr {
                converter.magicCookie = cookie
            }
        }

        var packetSize: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_PacketSizeUpperBound, &size, &packetSize) != noErr || packetSize == 0 {
            size = UInt32(MemoryLayout<UInt32>.size)
            _ = AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_MaximumPacketSize, &size, &packetSize)
        }
        maximumPacketSize = max(packetSize, 2048)
        compressedFormat = compressed
        self.converter = converter
        DanceLog.liveTranscription.info("Stream format: \(description.mSampleRate) Hz, \(description.mChannelsPerFrame) ch")
    }

    /// Decodes one run of packets the parser found.
    private func received(byteCount: UInt32, packetCount: UInt32, data: UnsafeRawPointer, descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard let compressedFormat, let converter, packetCount > 0, byteCount > 0 else { return }

        let input = AVAudioCompressedBuffer(
            format: compressedFormat,
            packetCapacity: AVAudioPacketCount(packetCount),
            maximumPacketSize: Int(max(maximumPacketSize, byteCount))
        )
        input.data.copyMemory(from: data, byteCount: Int(byteCount))
        if let descriptions, let destination = input.packetDescriptions {
            destination.update(from: descriptions, count: Int(packetCount))
        }
        input.packetCount = AVAudioPacketCount(packetCount)
        input.byteLength = byteCount

        // MP3 frames are 1152 samples, AAC 1024; room for either.
        let framesPerPacket = max(compressedFormat.streamDescription.pointee.mFramesPerPacket, 1152)
        guard let output = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: AVAudioFrameCount(packetCount) * framesPerPacket
        ) else { return }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        if status == .error {
            DanceLog.liveTranscription.error("Decode failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            return
        }
        if output.frameLength > 0 {
            onBuffer(output)
        }
    }
}

extension DanceLog {
    static let liveTranscription = DanceLog("LiveTranscription")
}
