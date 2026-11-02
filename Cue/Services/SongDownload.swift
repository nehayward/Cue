import Foundation
import OSLog
import SonosKit

/// One song's file coming down from its server into the playback cache,
/// written to disk as it arrives so the player can read it while it's still
/// on its way (`CachingStreamLoader`). A song playing from the server is
/// then fetched once, where it used to be fetched twice: once by the
/// player's stream and again by the cache for its copy.
///
/// A connection that drops picks up where it stopped, with a byte range,
/// a few times over; a pause (the cache letting a song further ahead wait
/// its turn) keeps what has arrived for the same. Everything about it runs
/// on `queue`, the resource loaders reading it included.
final class SongDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let queue = DispatchQueue(label: "dance.cue.songdownload", qos: .userInitiated)

    enum Failure: LocalizedError {
        case refused(StreamResponseCheck.Refused)
        case shortFile(Int64, of: Int64)
        case gaveUp(Error)

        var errorDescription: String? {
            switch self {
            case .refused(let refused): refused.errorDescription
            case .shortFile(let got, let length): "The server sent \(got) of \(length) bytes"
            case .gaveUp(let error): error.localizedDescription
            }
        }
    }

    let key: String
    let fileExtension: String
    /// The file's length, once the server has said.
    private(set) var expectedLength: Int64?
    private(set) var mimeType: String?
    /// Bytes on disk, from the top of the file.
    private(set) var written: Int64 = 0
    private(set) var isFinished = false
    private(set) var failure: Error?
    /// Where the bytes are: the partial file, then the cache's own copy.
    private(set) var fileURL: URL

    /// Cellular is allowed when the cache may fill over it, and always for
    /// a song the player is reading: it would have streamed it either way.
    var allowsCellular: Bool

    private let remote: URL
    private let destination: URL
    private let finished: (Result<Int64, Error>) -> Void
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var writer: FileHandle?
    private var isRunning = false
    private var isCancelled = false
    private var retries = 0
    private var observers: [UUID: () -> Void] = [:]

    private static let retryLimit = 5
    static let log = Logger(subsystem: "dance.cue", category: "playbackcache")

    /// `finished` is called on `queue` once the file is whole at
    /// `destination`, or the fetch is given up.
    init(key: String, remote: URL, fileExtension: String, partURL: URL, destination: URL, allowsCellular: Bool,
         finished: @escaping (Result<Int64, Error>) -> Void) {
        self.key = key
        self.remote = remote
        self.fileExtension = fileExtension
        self.fileURL = partURL
        self.destination = destination
        self.allowsCellular = allowsCellular
        self.finished = finished
        super.init()
        try? FileManager.default.removeItem(at: partURL)
        FileManager.default.createFile(atPath: partURL.path, contents: nil)
    }

    // MARK: - Control (on `queue`)

    /// Starts, or picks up from what has arrived.
    func run() {
        guard !isRunning, !isFinished, !isCancelled, failure == nil else { return }
        isRunning = true
        Self.log.notice("song download \(self.key, privacy: .public) \(self.written > 0 ? "picks up at \(self.written)" : "starts", privacy: .public)")
        var request = URLRequest(url: remote)
        request.allowsCellularAccess = allowsCellular
        request.allowsExpensiveNetworkAccess = allowsCellular
        request.allowsConstrainedNetworkAccess = allowsCellular
        if written > 0 {
            request.setValue("bytes=\(written)-", forHTTPHeaderField: "Range")
        }
        if session == nil {
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForResource = 30 * 60
            let delegateQueue = OperationQueue()
            delegateQueue.maxConcurrentOperationCount = 1
            delegateQueue.underlyingQueue = Self.queue
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
        }
        let task = session?.dataTask(with: request)
        self.task = task
        task?.resume()
    }

    /// Lets another song have the connection, keeping what has arrived.
    func pause() {
        guard isRunning else { return }
        isRunning = false
        task?.cancel()
        task = nil
    }

    /// Drops the fetch and what it had.
    func cancel() {
        guard !isFinished, !isCancelled else { return }
        isCancelled = true
        isRunning = false
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        try? writer?.close()
        writer = nil
        try? FileManager.default.removeItem(at: fileURL)
        failure = CancellationError()
        notify()
    }

    /// Calls `block` on `queue` whenever bytes arrive, the length becomes
    /// known, or the fetch ends either way.
    @discardableResult
    func observe(_ block: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = block
        return id
    }

    func stopObserving(_ id: UUID) {
        observers[id] = nil
    }

    /// Up to `length` bytes from `offset`, of what has arrived.
    func read(at offset: Int64, length: Int) -> Data? {
        let available = (isFinished ? (expectedLength ?? written) : written) - offset
        guard available > 0, length > 0, let reader = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? reader.close() }
        try? reader.seek(toOffset: UInt64(offset))
        return try? reader.read(upToCount: Int(min(Int64(length), available)))
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard dataTask === task else { return completionHandler(.cancel) }
        if let refused = StreamResponseCheck.refusal(in: response) {
            completionHandler(.cancel)
            fail(Failure.refused(refused))
            return
        }
        let http = response as? HTTPURLResponse
        if http?.statusCode == 206 {
            // Picking up: the total is after the slash of "bytes a-b/total".
            if let range = http?.value(forHTTPHeaderField: "Content-Range"),
               let total = range.split(separator: "/").last.flatMap({ Int64($0) }) {
                expectedLength = total
            }
        } else {
            // The whole file, from the top, even if a range was asked for.
            if written > 0 {
                try? writer?.truncate(atOffset: 0)
                written = 0
            }
            if response.expectedContentLength > 0 {
                expectedLength = response.expectedContentLength
            }
        }
        mimeType = response.mimeType
        retries = 0
        notify()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard dataTask === task else { return }
        if writer == nil {
            writer = try? FileHandle(forWritingTo: fileURL)
        }
        guard let writer else {
            fail(CocoaError(.fileWriteUnknown))
            return
        }
        do {
            try writer.seek(toOffset: UInt64(written))
            try writer.write(contentsOf: data)
        } catch {
            fail(error)
            return
        }
        written += Int64(data.count)
        notify()
    }

    func urlSession(_ session: URLSession, task finishedTask: URLSessionTask, didCompleteWithError error: Error?) {
        guard finishedTask === task else { return }
        task = nil
        isRunning = false
        guard !isCancelled, failure == nil else { return }
        if error == nil, let expectedLength, written >= expectedLength {
            finish()
            return
        }
        if error == nil, expectedLength == nil, written > 0 {
            // No length was given; the server closing is the end.
            expectedLength = written
            finish()
            return
        }
        // Dropped partway: pick up from here after a moment, a few times.
        retries += 1
        guard retries <= Self.retryLimit else {
            fail(error.map { Failure.gaveUp($0) } ?? Failure.shortFile(written, of: expectedLength ?? 0))
            return
        }
        let delay = min(pow(2, Double(retries)), 30)
        Self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.run()
        }
    }

    // MARK: - Ending

    private func finish() {
        try? writer?.close()
        writer = nil
        session?.finishTasksAndInvalidate()
        session = nil
        try? FileManager.default.removeItem(at: destination)
        if (try? FileManager.default.moveItem(at: fileURL, to: destination)) != nil {
            fileURL = destination
        }
        isFinished = true
        Self.log.notice("song download \(self.key, privacy: .public) done: \(self.written) bytes")
        notify()
        finished(.success(written))
    }

    private func fail(_ error: Error) {
        guard failure == nil else { return }
        failure = error
        isRunning = false
        Self.log.error("song download \(self.key, privacy: .public) failed at \(self.written) bytes: \(error.localizedDescription, privacy: .public)")
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        try? writer?.close()
        writer = nil
        try? FileManager.default.removeItem(at: fileURL)
        notify()
        finished(.failure(error))
    }

    private func notify() {
        for observer in observers.values {
            observer()
        }
    }
}
