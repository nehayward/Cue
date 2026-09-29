import Foundation
import Network

/// Keeps the last stretch of a live station on the device, so it can be
/// played back from any point inside it: a minute back, picked up again
/// after a pause, or live.
///
/// Most TuneIn stations are Icecast or Shoutcast MP3 and AAC, and
/// `AVPlayer` keeps almost nothing behind the live point of those — there
/// is nowhere to seek back to. So Cue records the stream itself: the buffer
/// downloads it, strips the ICY titles out of the audio (keeping them, with
/// the moment each one aired), splits the audio into frames to know how
/// much time it holds, and `LiveRadioServer` serves it to the player over
/// loopback from any frame. The player sees an ordinary live stream that
/// happens to start wherever it was asked to.
///
/// All of its state lives on `LiveRadioServer.queue`; the main actor reads
/// it through the synchronous accessors.
final class LiveRadioBuffer: @unchecked Sendable {
    enum Format {
        case mp3
        case adts

        var mimeType: String {
            switch self {
            case .mp3: "audio/mpeg"
            case .adts: "audio/aac"
            }
        }

        var fileExtension: String {
            switch self {
            case .mp3: "mp3"
            case .adts: "aac"
            }
        }
    }

    /// How far back a station can be taken.
    static let window: TimeInterval = 15 * 60
    /// A ceiling for a high-bitrate station: 15 minutes at 320 kbps is
    /// about 36 MB.
    private static let maxBytes = 48 * 1024 * 1024
    /// How far behind the live point "live" starts a player: a burst it can
    /// buffer at once, rather than waiting on the air in real time.
    private static let liveLead: TimeInterval = 4
    /// Spacing of the points a player can start from.
    private static let checkpointSpacing: TimeInterval = 0.25

    let id = UUID()
    let format: Format
    /// The station's bitrate in kbps, when its server says.
    let bitrate: Int?

    private let queue = LiveRadioServer.shared.queue
    private let sourceURL: URL
    private let port: UInt16
    private var session: URLSession?
    private var reconnects = 0
    private var stopped = false
    /// The upstream is gone for good; readers drain what's left and close.
    private var finished = false

    // ICY: `metaInterval` bytes of audio, a length byte, then that many
    // sixteen-byte blocks of `StreamTitle='…';`.
    private var metaInterval: Int?
    private var audioUntilMeta = 0
    private var metaRemaining = 0
    private var metaBytes: [UInt8] = []

    // The audio, as the absolute offsets the server addresses it by.
    private var storage: [UInt8] = []
    /// The absolute offset of `storage[0]`.
    private var baseOffset: Int64 = 0
    /// Everything before this is whole frames.
    private var parsed: Int64 = 0
    /// Media time at `parsed` — seconds of audio received so far.
    private var mediaTime: TimeInterval = 0
    /// Whether `parsed` sits on a frame the next one confirmed.
    private var synced = false
    /// Frame starts a player can begin at, oldest first.
    private var checkpoints: [(offset: Int64, time: TimeInterval)] = []
    /// ICY titles and the moment in the stream each one aired, oldest first.
    private var titles: [(time: TimeInterval, title: String)] = []
    /// Readers caught up with the live point, woken by the next frames.
    private var waiters: [() -> Void] = []

    private init(sourceURL: URL, format: Format, bitrate: Int?, metaInterval: Int?, port: UInt16) {
        self.sourceURL = sourceURL
        self.format = format
        self.bitrate = bitrate
        self.metaInterval = metaInterval
        self.audioUntilMeta = metaInterval ?? 0
        self.port = port
    }

    // MARK: - Opening

    /// Connects to `url` and starts recording it. Nil when the stream isn't
    /// one the buffer can split into frames (HLS, Ogg, a playlist) or the
    /// relay can't listen — the caller then plays the station directly,
    /// without rewind.
    static func open(_ url: URL) async -> LiveRadioBuffer? {
        guard let port = await LiveRadioServer.shared.start() else { return nil }
        let upstream = Upstream()
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: upstream, delegateQueue: LiveRadioServer.shared.operationQueue)
        let opened: LiveRadioBuffer? = await withCheckedContinuation { continuation in
            upstream.onResponse = { response in
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let format = Self.format(of: http, url: url) else {
                    continuation.resume(returning: nil)
                    return false
                }
                let buffer = LiveRadioBuffer(
                    sourceURL: url,
                    format: format,
                    bitrate: http.value(forHTTPHeaderField: "icy-br").flatMap { Int($0.split(separator: ",").first ?? "") },
                    metaInterval: http.value(forHTTPHeaderField: "icy-metaint").flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil },
                    port: port
                )
                buffer.session = session
                upstream.buffer = buffer
                LiveRadioServer.shared.register(buffer)
                continuation.resume(returning: buffer)
                return true
            }
            upstream.onFailure = {
                continuation.resume(returning: nil)
            }
            session.dataTask(with: Self.request(for: url)).resume()
        }
        if opened == nil {
            session.invalidateAndCancel()
        }
        return opened
    }

    private static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // Titles inline, so each one lands at the moment it aired.
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        return request
    }

    private static func format(of response: HTTPURLResponse, url: URL) -> Format? {
        let mime = response.mimeType?.lowercased() ?? ""
        let fileExtension = (response.url ?? url).pathExtension.lowercased()
        if mime.contains("mpegurl") || mime.contains("ogg") || mime.contains("opus") || fileExtension == "m3u8" {
            return nil
        }
        if mime.contains("aac") {
            return .adts
        }
        if mime.contains("mpeg") || mime.contains("mp3") {
            return .mp3
        }
        // A server that only says "audio" or "octet-stream": trust the name.
        switch fileExtension {
        case "mp3": return .mp3
        case "aac": return .adts
        default: return nil
        }
    }

    /// Stops recording and closes every reader.
    func stop() {
        queue.async { [self] in
            guard !stopped else { return }
            stopped = true
            finish()
            session?.invalidateAndCancel()
            session = nil
            LiveRadioServer.shared.unregister(self)
        }
    }

    // MARK: - Reading, for the main actor

    struct Window: Equatable {
        /// The oldest moment still held.
        var start: TimeInterval
        /// The newest.
        var live: TimeInterval
    }

    /// What the buffer holds, in stream seconds.
    var window: Window {
        queue.sync {
            Window(start: checkpoints.first?.time ?? mediaTime, live: mediaTime)
        }
    }

    /// Whether a player pointed at the buffer now would be served: the
    /// station is still coming in and the relay is still listening. A
    /// suspended app can lose both.
    var isHealthy: Bool {
        queue.sync {
            !finished && !stopped && LiveRadioServer.shared.listeningPort == port
        }
    }

    /// The ICY title on air at `time`, if the station sends them.
    func title(at time: TimeInterval) -> String? {
        queue.sync {
            titles.last(where: { $0.time <= time })?.title
        }
    }

    /// The URL a player opens to hear the station from `time` on — the
    /// frame at or just before it — and the stream time that URL starts
    /// at. Nil `time` is live.
    func source(at time: TimeInterval?) -> (url: URL, start: TimeInterval) {
        queue.sync {
            let target = time ?? (mediaTime - Self.liveLead)
            let checkpoint = checkpoints.last(where: { $0.time <= target })
                ?? checkpoints.first
                ?? (offset: parsed, time: mediaTime)
            let url = URL(string: "http://127.0.0.1:\(port)/\(id.uuidString)/\(checkpoint.offset).\(format.fileExtension)")!
            return (url, checkpoint.time)
        }
    }

    // MARK: - Serving (on `queue`)

    enum Chunk {
        case data(Data)
        case wait
        case end
    }

    /// Up to `limit` bytes from `cursor` on, moving it past them. A cursor
    /// the window has already dropped moves up to the oldest frame held.
    func read(from cursor: inout Int64, limit: Int) -> Chunk {
        dispatchPrecondition(condition: .onQueue(queue))
        if cursor < baseOffset {
            cursor = checkpoints.first?.offset ?? baseOffset
        }
        guard cursor < parsed else {
            return finished ? .end : .wait
        }
        let start = Int(cursor - baseOffset)
        let end = Int(min(parsed, cursor + Int64(limit)) - baseOffset)
        cursor = baseOffset + Int64(end)
        return .data(Data(storage[start..<end]))
    }

    /// Calls `wake` once more of the stream is in, or when it ends.
    func waitForData(_ wake: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        if finished {
            wake()
        } else {
            waiters.append(wake)
        }
    }

    // MARK: - Ingest (on `queue`)

    fileprivate func receive(_ data: Data) {
        guard !stopped else { return }
        reconnects = 0
        guard let interval = metaInterval else {
            append(audio: data)
            return
        }
        var index = data.startIndex
        while index < data.endIndex {
            if metaRemaining > 0 {
                let count = min(metaRemaining, data.endIndex - index)
                metaBytes.append(contentsOf: data[index..<(index + count)])
                index += count
                metaRemaining -= count
                if metaRemaining == 0 {
                    noteMetadata(metaBytes)
                    metaBytes.removeAll(keepingCapacity: true)
                    audioUntilMeta = interval
                }
            } else if audioUntilMeta == 0 {
                let length = Int(data[index]) * 16
                index += 1
                if length == 0 {
                    audioUntilMeta = interval
                } else {
                    metaRemaining = length
                }
            } else {
                let count = min(audioUntilMeta, data.endIndex - index)
                append(audio: data[index..<(index + count)])
                index += count
                audioUntilMeta -= count
            }
        }
    }

    /// The connection dropped. Try it again a few times — a phone moving
    /// between networks drops a stream every so often — and give up after
    /// that; readers then drain what's held and close.
    fileprivate func upstreamEnded() {
        guard !stopped, !finished else { return }
        guard reconnects < 3 else {
            finish()
            return
        }
        reconnects += 1
        let delay = Double(reconnects) * 2
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            guard !stopped, !finished, let session else { return }
            // A new connection starts on a new ICY count, and anywhere in a
            // frame: resync on the next one.
            audioUntilMeta = metaInterval ?? 0
            metaRemaining = 0
            metaBytes.removeAll()
            synced = false
            session.dataTask(with: Self.request(for: sourceURL)).resume()
        }
    }

    /// A reconnect answered in a shape the buffer can't follow.
    fileprivate func upstreamChanged(to response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              Self.format(of: http, url: sourceURL) == format else {
            finish()
            return false
        }
        metaInterval = http.value(forHTTPHeaderField: "icy-metaint").flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
        audioUntilMeta = metaInterval ?? 0
        return true
    }

    private func finish() {
        finished = true
        wakeReaders()
    }

    private func wakeReaders() {
        let woken = waiters
        waiters = []
        woken.forEach { $0() }
    }

    private func noteMetadata(_ bytes: [UInt8]) {
        let text = String(bytes: bytes, encoding: .utf8)
            ?? String(bytes: bytes, encoding: .isoLatin1)
            ?? ""
        guard let start = text.range(of: "StreamTitle='") else { return }
        let rest = text[start.upperBound...]
        let end = rest.range(of: "';")?.lowerBound ?? rest.firstIndex(of: "'") ?? rest.endIndex
        let title = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, titles.last?.title != title else { return }
        titles.append((mediaTime, title))
    }

    private func append<Bytes: Collection>(audio: Bytes) where Bytes.Element == UInt8 {
        storage.append(contentsOf: audio)
        let before = parsed
        parseFrames()
        trim()
        if parsed > before {
            wakeReaders()
        }
    }

    /// Walks whole frames from `parsed`, adding up their length in time and
    /// leaving a checkpoint every so often. On losing sync (the start of the
    /// stream, a reconnect, a stray tag) it steps a byte at a time until a
    /// frame header is followed by another one.
    private func parseFrames() {
        let headerLength = format == .mp3 ? 4 : 7
        while true {
            let local = Int(parsed - baseOffset)
            let available = storage.count - local
            guard available >= headerLength else { return }
            guard let frame = header(at: local) else {
                synced = false
                parsed += 1
                continue
            }
            if !synced {
                guard available >= frame.length + headerLength else { return }
                guard header(at: local + frame.length) != nil else {
                    parsed += 1
                    continue
                }
                synced = true
            }
            guard available >= frame.length else { return }
            if checkpoints.last.map({ mediaTime - $0.time >= Self.checkpointSpacing }) ?? true {
                checkpoints.append((parsed, mediaTime))
            }
            parsed += Int64(frame.length)
            mediaTime += frame.duration
        }
    }

    /// Drops what has fallen out of the window, a stretch at a time rather
    /// than on every packet.
    private func trim() {
        guard let first = checkpoints.first else { return }
        let overTime = mediaTime - first.time > Self.window + 30
        let overBytes = storage.count > Self.maxBytes + 4 * 1024 * 1024
        guard overTime || overBytes else { return }
        var keep = checkpoints.firstIndex(where: { $0.time >= mediaTime - Self.window }) ?? checkpoints.count - 1
        while keep < checkpoints.count - 1, parsed - checkpoints[keep].offset > Int64(Self.maxBytes) {
            keep += 1
        }
        let cut = checkpoints[keep]
        storage.removeFirst(Int(cut.offset - baseOffset))
        baseOffset = cut.offset
        checkpoints.removeFirst(keep)
        // The title on air at the new start still names what plays there.
        if let lastBefore = titles.lastIndex(where: { $0.time <= cut.time }), lastBefore > 0 {
            titles.removeFirst(lastBefore)
        }
    }

    // MARK: - Frame headers

    private struct Frame {
        var length: Int
        var duration: TimeInterval
    }

    private func header(at index: Int) -> Frame? {
        switch format {
        case .mp3: mp3Header(at: index)
        case .adts: adtsHeader(at: index)
        }
    }

    private static let mp3Bitrates: [[Int]] = [
        // MPEG-1 layers I, II, III
        [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
        [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
        // MPEG-2 and 2.5 layer I, then layers II and III
        [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
        [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
    ]

    private func mp3Header(at index: Int) -> Frame? {
        let b1 = storage[index + 1], b2 = storage[index + 2]
        guard storage[index] == 0xFF, b1 & 0xE0 == 0xE0 else { return nil }
        let version = (b1 >> 3) & 0x3  // 0: 2.5, 1: reserved, 2: 2, 3: 1
        let layer = (b1 >> 1) & 0x3  // 1: III, 2: II, 3: I
        let bitrateIndex = Int(b2 >> 4)
        let rateIndex = Int((b2 >> 2) & 0x3)
        guard version != 1, layer != 0, bitrateIndex != 0, bitrateIndex != 15, rateIndex != 3 else { return nil }

        let isV1 = version == 3
        let table = isV1 ? Int(3 - layer) : (layer == 3 ? 3 : 4)
        let bitrate = Self.mp3Bitrates[table][bitrateIndex] * 1000
        let baseRates = [44_100, 48_000, 32_000]
        let sampleRate = baseRates[rateIndex] / (isV1 ? 1 : (version == 2 ? 2 : 4))
        let samples = switch layer {
        case 3: 384
        case 2: 1152
        default: isV1 ? 1152 : 576
        }
        let padding = Int((b2 >> 1) & 0x1)
        // Layer I counts in four-byte slots.
        let length = layer == 3
            ? (12 * bitrate / sampleRate + padding) * 4
            : samples / 8 * bitrate / sampleRate + padding
        guard length > 4 else { return nil }
        return Frame(length: length, duration: Double(samples) / Double(sampleRate))
    }

    private static let adtsRates = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000, 7_350]

    private func adtsHeader(at index: Int) -> Frame? {
        let b1 = storage[index + 1], b2 = storage[index + 2]
        guard storage[index] == 0xFF, b1 & 0xF6 == 0xF0 else { return nil }
        let rateIndex = Int((b2 >> 2) & 0xF)
        guard rateIndex < Self.adtsRates.count else { return nil }
        let length = (Int(storage[index + 3] & 0x3) << 11) | (Int(storage[index + 4]) << 3) | (Int(storage[index + 5]) >> 5)
        guard length > 7 else { return nil }
        let blocks = Int(storage[index + 6] & 0x3) + 1
        // HE-AAC names its core rate here, and its frames are 1024 samples
        // at that rate — the same length in time as the doubled output.
        return Frame(length: length, duration: Double(1024 * blocks) / Double(Self.adtsRates[rateIndex]))
    }
}

// MARK: - Upstream

/// The station's connection. Owned by its `URLSession` until the buffer
/// invalidates it.
private final class Upstream: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// Answers whether the response can be recorded; only for the first one.
    var onResponse: ((URLResponse) -> Bool)?
    var onFailure: (() -> Void)?
    weak var buffer: LiveRadioBuffer?

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let onResponse {
            self.onResponse = nil
            onFailure = nil
            completionHandler(onResponse(response) ? .allow : .cancel)
        } else if let buffer {
            completionHandler(buffer.upstreamChanged(to: response) ? .allow : .cancel)
        } else {
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer?.receive(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let onFailure {
            onFailure()
            self.onFailure = nil
            onResponse = nil
            return
        }
        buffer?.upstreamEnded()
    }
}

// MARK: - Loopback server

/// Serves every open `LiveRadioBuffer` to the player on `127.0.0.1`, one
/// URL per starting frame: `/<buffer id>/<byte offset>.<mp3|aac>`. The
/// response is shaped like an Icecast server's — no length, no ranges, the
/// audio until the station ends — which `AVPlayer` already plays as a live
/// stream. A reader that catches up with the air waits for the next frames,
/// so a stream that started a minute back stays a minute back.
final class LiveRadioServer: @unchecked Sendable {
    static let shared = LiveRadioServer()

    let queue = DispatchQueue(label: "dance.cue.liveRadio", qos: .userInitiated)
    let operationQueue: OperationQueue

    private var listener: NWListener?
    private var port: UInt16?
    private var pendingStarts: [CheckedContinuation<UInt16?, Never>] = []
    private var buffers: [UUID: LiveRadioBuffer] = [:]
    private var connections: [ObjectIdentifier: LiveRadioConnection] = [:]

    private init() {
        operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.underlyingQueue = queue
    }

    /// The port while the listener is up; read on `queue`. Suspension can
    /// take it down, and the next `start()` brings it back on a new one.
    fileprivate var listeningPort: UInt16? {
        dispatchPrecondition(condition: .onQueue(queue))
        return port
    }

    /// The port the server listens on, starting it if it isn't.
    func start() async -> UInt16? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if let port {
                    continuation.resume(returning: port)
                    return
                }
                pendingStarts.append(continuation)
                guard listener == nil else { return }
                do {
                    let parameters = NWParameters.tcp
                    parameters.acceptLocalOnly = true
                    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
                    let listener = try NWListener(using: parameters)
                    listener.newConnectionHandler = { [weak self] connection in
                        self?.accept(connection)
                    }
                    listener.stateUpdateHandler = { [weak self, weak listener] state in
                        guard let self, let listener else { return }
                        switch state {
                        case .ready:
                            port = listener.port?.rawValue
                            resolveStarts()
                        case .failed, .cancelled:
                            listener.cancel()
                            if self.listener === listener {
                                self.listener = nil
                                port = nil
                            }
                            resolveStarts()
                        default:
                            break
                        }
                    }
                    self.listener = listener
                    listener.start(queue: queue)
                } catch {
                    resolveStarts()
                }
            }
        }
    }

    private func resolveStarts() {
        let waiting = pendingStarts
        pendingStarts = []
        waiting.forEach { $0.resume(returning: port) }
    }

    func register(_ buffer: LiveRadioBuffer) {
        dispatchPrecondition(condition: .onQueue(queue))
        buffers[buffer.id] = buffer
    }

    func unregister(_ buffer: LiveRadioBuffer) {
        dispatchPrecondition(condition: .onQueue(queue))
        buffers[buffer.id] = nil
    }

    fileprivate func buffer(for id: UUID) -> LiveRadioBuffer? {
        buffers[id]
    }

    private func accept(_ connection: NWConnection) {
        let reader = LiveRadioConnection(connection: connection, server: self)
        connections[ObjectIdentifier(reader)] = reader
        reader.start(on: queue)
    }

    fileprivate func closed(_ reader: LiveRadioConnection) {
        connections[ObjectIdentifier(reader)] = nil
    }
}

/// One player's request: reads it, then pumps the buffer to it from the
/// frame it asked for.
private final class LiveRadioConnection {
    private let connection: NWConnection
    private weak var server: LiveRadioServer?
    private var request = Data()
    private var buffer: LiveRadioBuffer?
    private var cursor: Int64 = 0
    private var isClosed = false

    init(connection: NWConnection, server: LiveRadioServer) {
        self.connection = connection
        self.server = server
    }

    func start(on queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.close()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest()
    }

    private func receiveRequest() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self, !isClosed else { return }
            if let data { request.append(data) }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                respond()
            } else if isComplete || error != nil || request.count > 16_384 {
                close()
            } else {
                receiveRequest()
            }
        }
    }

    /// `GET /<id>/<offset>.<ext>`. Range headers are ignored, as an Icecast
    /// server ignores them.
    private func respond() {
        let line = String(decoding: request.prefix { $0 != 0x0D }, as: UTF8.self)
        let parts = line.split(separator: " ")
        let path = parts.count > 1 ? parts[1].split(separator: "/") : []
        guard parts.count > 1,
              path.count == 2,
              let id = UUID(uuidString: String(path[0])),
              let offset = Int64(path[1].split(separator: ".").first ?? ""),
              let buffer = server?.buffer(for: id) else {
            send(header: "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", thenPump: false)
            return
        }
        self.buffer = buffer
        cursor = offset
        var header = "HTTP/1.1 200 OK\r\nContent-Type: \(buffer.format.mimeType)\r\nCache-Control: no-cache, no-store\r\nConnection: close\r\n"
        if let bitrate = buffer.bitrate {
            header += "icy-br: \(bitrate)\r\n"
        }
        header += "\r\n"
        send(header: header, thenPump: parts[0] != "HEAD")
        watchForHangUp()
    }

    /// A player that moves on just closes its end; notice while waiting on
    /// the air rather than on the next send.
    private func watchForHangUp() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, isComplete, error in
            guard let self, !isClosed else { return }
            if isComplete || error != nil {
                close()
            } else {
                watchForHangUp()
            }
        }
    }

    private func send(header: String, thenPump: Bool) {
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil || !thenPump {
                finish()
            } else {
                pump()
            }
        })
    }

    private func pump() {
        guard !isClosed, let buffer else { return }
        switch buffer.read(from: &cursor, limit: 64 * 1024) {
        case .data(let chunk):
            connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
                if error != nil {
                    self?.close()
                } else {
                    self?.pump()
                }
            })
        case .wait:
            buffer.waitForData { [weak self] in
                self?.pump()
            }
        case .end:
            finish()
        }
    }

    private func finish() {
        guard !isClosed else { return }
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.close()
        })
    }

    private func close() {
        guard !isClosed else { return }
        isClosed = true
        buffer = nil
        connection.cancel()
        server?.closed(self)
    }
}
