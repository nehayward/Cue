import AudioToolbox
import AVFoundation
import OSLog

/// A book's M4B on the server, opened where it is: AudioToolbox reads it
/// through callbacks that answer from the file's index, fetched whole once,
/// and fetch the rest in ranges as they're asked for, so a stretch deep in
/// a 20-hour file costs its index and that stretch alone. Unlike an MP3, an
/// M4B can't be decoded from a piece found by reckoning: its packets are
/// placed only by the index (`moov`), which can be at either end.
///
/// Every read can wait on the network, so a file is opened and read on a
/// thread of its own (`BookTranscriptionEngine.read(mp4:)`), never on Swift
/// concurrency's.
final class RemoteBookFile: @unchecked Sendable {
    /// A stretch of the file's bytes and where it starts.
    struct Piece: Sendable {
        let start: Int64
        let data: Data

        func contains(_ position: Int64) -> Bool {
            position >= start && position < start + Int64(data.count)
        }
    }

    /// How much of the file is asked for at a time past the kept pieces:
    /// about a minute of a book at 64 kbps.
    private static let blockSize: Int64 = 512 * 1024
    private static let blocksKept = 6

    let url: URL
    let length: Int64
    /// What's held for the file's whole life: its head and its index.
    private let kept: [Piece]

    private let lock = NSLock()
    private var blocks: [Int64: Data] = [:]
    /// Block numbers, the latest used last.
    private var recent: [Int64] = []
    private var fetching: URLSessionDataTask?
    private var cancelled = false

    init(url: URL, length: Int64, kept: [Piece]) {
        self.url = url
        self.length = length
        self.kept = kept
    }

    var isCancelled: Bool { lock.withLock { cancelled } }

    /// Stops any fetch under way, and every read after it fails.
    func cancel() {
        lock.withLock {
            cancelled = true
            fetching?.cancel()
        }
    }

    /// Copies `count` bytes from `position` into `buffer`, fewer at the
    /// file's end; nil when a fetch fails.
    func read(at position: Int64, count: Int, into buffer: UnsafeMutableRawPointer) -> Int? {
        let end = min(position + Int64(count), length)
        guard position < end else { return 0 }
        var at = position
        while at < end {
            guard let piece = piece(containing: at) else { return nil }
            let from = Int(at - piece.start)
            let take = min(Int(end - at), piece.data.count - from)
            guard take > 0 else { return nil }
            piece.data.withUnsafeBytes { bytes in
                (buffer + Int(at - position)).copyMemory(from: bytes.baseAddress! + from, byteCount: take)
            }
            at += Int64(take)
        }
        return Int(end - position)
    }

    private func piece(containing position: Int64) -> Piece? {
        if let piece = kept.first(where: { $0.contains(position) }) { return piece }
        let block = position / Self.blockSize
        let start = block * Self.blockSize
        if let data = lock.withLock({ () -> Data? in
            guard let data = blocks[block] else { return nil }
            recent.removeAll { $0 == block }
            recent.append(block)
            return data
        }) {
            return Piece(start: start, data: data)
        }
        guard let data = fetch(start..<min(start + Self.blockSize, length)) else { return nil }
        lock.withLock {
            blocks[block] = data
            recent.append(block)
            while recent.count > Self.blocksKept {
                blocks[recent.removeFirst()] = nil
            }
        }
        return Piece(start: start, data: data)
    }

    /// The bytes in `range`, waited for.
    private func fetch(_ range: Range<Int64>) -> Data? {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 30
        let done = DispatchSemaphore(value: 0)
        let answer = Answer()
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 206 { answer.data = data }
            done.signal()
        }
        guard lock.withLock({ () -> Bool in
            guard !cancelled else { return false }
            fetching = task
            return true
        }) else { return nil }
        task.resume()
        done.wait()
        lock.withLock { fetching = nil }
        return answer.data
    }

    private final class Answer: @unchecked Sendable {
        var data: Data?
    }
}

// MARK: - The index

extension RemoteBookFile {
    /// The file's index, found by walking its top-level boxes from `head`
    /// (the file's first bytes) and fetched whole; the last few files'
    /// are kept, so a seek that starts a read again doesn't fetch it again.
    static func index(of url: URL, length: Int64, head: Data) async -> Piece? {
        let key = url.absoluteString.split(separator: "?").first.map(String.init) ?? url.absoluteString
        if let piece = keptIndexes.piece(for: key) { return piece }
        let head = Piece(start: 0, data: head)
        var offset: Int64 = 0
        while offset + 8 <= length {
            guard let header = await bytes(of: url, offset..<min(offset + 16, length), head: head),
                  header.count >= 8 else { return nil }
            let fields = [UInt8](header)
            var size = fields[0..<4].reduce(Int64(0)) { $0 << 8 | Int64($1) }
            let type = String(decoding: fields[4..<8], as: UTF8.self)
            if size == 1, fields.count >= 16 {
                size = fields[8..<16].reduce(Int64(0)) { $0 << 8 | Int64($1) }
            } else if size == 0 {
                size = length - offset
            }
            guard size >= 8 else { return nil }
            if type == "moov" {
                // An index this big is no book's; don't hold it.
                guard size <= 64 * 1024 * 1024,
                      let data = await bytes(of: url, offset..<offset + size, head: head),
                      data.count == Int(size) else { return nil }
                let piece = Piece(start: offset, data: data)
                keptIndexes.keep(piece, for: key)
                return piece
            }
            offset += size
        }
        return nil
    }

    private static func bytes(of url: URL, _ range: Range<Int64>, head: Piece) async -> Data? {
        if head.contains(range.lowerBound), head.contains(range.upperBound - 1) {
            return head.data.subdata(in: Int(range.lowerBound)..<Int(range.upperBound))
        }
        var request = URLRequest(url: url)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 30
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 206 else { return nil }
        return data
    }

    private static let keptIndexes = KeptIndexes()

    private final class KeptIndexes: @unchecked Sendable {
        private let lock = NSLock()
        private var pieces: [(key: String, piece: Piece)] = []

        func piece(for key: String) -> Piece? {
            lock.withLock { pieces.first { $0.key == key }?.piece }
        }

        func keep(_ piece: Piece, for key: String) {
            lock.withLock {
                pieces.removeAll { $0.key == key }
                pieces.append((key, piece))
                if pieces.count > 3 { pieces.removeFirst() }
            }
        }
    }
}

// MARK: - Decoding

/// A `RemoteBookFile` opened by AudioToolbox and decoded to PCM, which
/// seeks by the file's own index, to the sample. Used on one thread.
final class RemoteBookAudio {
    let format: AVAudioFormat
    private let file: RemoteBookFile
    private let audioFile: AudioFileID
    private let reader: ExtAudioFileRef

    init?(_ file: RemoteBookFile) {
        var opened: AudioFileID?
        let status = AudioFileOpenWithCallbacks(
            Unmanaged.passUnretained(file).toOpaque(),
            { client, position, count, buffer, actual in
                let file = Unmanaged<RemoteBookFile>.fromOpaque(client).takeUnretainedValue()
                guard let read = file.read(at: position, count: Int(count), into: buffer) else {
                    actual.pointee = 0
                    return kAudioFileUnspecifiedError
                }
                actual.pointee = UInt32(read)
                return noErr
            },
            nil,
            { client in Unmanaged<RemoteBookFile>.fromOpaque(client).takeUnretainedValue().length },
            nil,
            kAudioFileM4AType,
            &opened
        )
        guard status == noErr, let audioFile = opened else {
            Logger.bookTranscript.error("AudioToolbox couldn't open the book file: \(status)")
            return nil
        }
        var wrapped: ExtAudioFileRef?
        guard ExtAudioFileWrapAudioFileID(audioFile, false, &wrapped) == noErr, let reader = wrapped else {
            AudioFileClose(audioFile)
            return nil
        }
        var described = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard ExtAudioFileGetProperty(reader, kExtAudioFileProperty_FileDataFormat, &size, &described) == noErr,
              let format = AVAudioFormat(standardFormatWithSampleRate: described.mSampleRate, channels: max(described.mChannelsPerFrame, 1)) else {
            ExtAudioFileDispose(reader)
            AudioFileClose(audioFile)
            return nil
        }
        var client = format.streamDescription.pointee
        guard ExtAudioFileSetProperty(reader, kExtAudioFileProperty_ClientDataFormat, size, &client) == noErr else {
            ExtAudioFileDispose(reader)
            AudioFileClose(audioFile)
            return nil
        }
        self.format = format
        self.file = file
        self.audioFile = audioFile
        self.reader = reader
    }

    deinit {
        ExtAudioFileDispose(reader)
        AudioFileClose(audioFile)
    }

    /// Moves to `time` in the file, returning where it landed; nil when it
    /// can't.
    func seek(to time: TimeInterval) -> TimeInterval? {
        let frame = Int64(max(time, 0) * format.sampleRate)
        guard ExtAudioFileSeek(reader, frame) == noErr else { return nil }
        return Double(frame) / format.sampleRate
    }

    /// Up to `frames` of audio from where it is; nil at the end or when
    /// the file can't be read on.
    func read(_ frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        // The buffer list's sizes follow the frame length: full, to be read into.
        buffer.frameLength = frames
        var count = UInt32(frames)
        guard ExtAudioFileRead(reader, &count, buffer.mutableAudioBufferList) == noErr, count > 0 else { return nil }
        buffer.frameLength = count
        return buffer
    }
}
