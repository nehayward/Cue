import AVFoundation
import UniformTypeIdentifiers

/// Feeds a stream player item from its song's `SongDownload` rather than
/// letting the player fetch the file itself, so the bytes the player hears
/// are the ones the cache keeps. The player's range requests are answered
/// from the file as it arrives; one well past what has arrived (a drag far
/// ahead) is fetched from the server on its own, for that stretch only, so
/// the drag doesn't wait for the download to get there.
///
/// Kept alive by its asset (`makeAsset(for:)`) and run on
/// `SongDownload.queue`, like the download it reads.
final class CachingStreamLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate, @unchecked Sendable {
    private static let scheme = "cue-stream"
    /// A request starting further past what has arrived than this is
    /// fetched on its own.
    private static let reachAhead: Int64 = 1_000_000
    /// The most read from disk for one answer.
    private static let chunk = 256 * 1024
    private static var assetKey = 0

    private let download: SongDownload
    private let remote: URL
    private let released: @MainActor () -> Void
    private var requests: [AVAssetResourceLoadingRequest] = []
    private var observation: UUID?
    /// Requests far ahead being fetched on their own, by their fetch.
    private var reaches: [Int: AVAssetResourceLoadingRequest] = [:]
    /// A session holds its delegate strongly: it gets a stand-in that
    /// doesn't, so the loader still goes with its asset.
    private lazy var reachSession: URLSession = {
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.underlyingQueue = SongDownload.queue
        return URLSession(configuration: .default, delegate: WeakDataDelegate(self), delegateQueue: delegateQueue)
    }()
    private var hasReachSession = false

    private init(download: SongDownload, remote: URL, released: @escaping @MainActor () -> Void) {
        self.download = download
        self.remote = remote
        self.released = released
        super.init()
    }

    /// An asset that plays `remote` through `download`. `released` is
    /// called once the asset, and with it the loader, is gone.
    static func makeAsset(for download: SongDownload, remote: URL, released: @escaping @MainActor () -> Void) -> AVURLAsset? {
        guard var components = URLComponents(url: remote, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = scheme
        guard let url = components.url else { return nil }
        let loader = CachingStreamLoader(download: download, remote: remote, released: released)
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(loader, queue: SongDownload.queue)
        // The resource loader holds its delegate weakly: the asset keeps it.
        objc_setAssociatedObject(asset, &assetKey, loader, .OBJC_ASSOCIATION_RETAIN)
        SongDownload.queue.async {
            loader.observation = download.observe { [weak loader] in loader?.serve() }
        }
        return asset
    }

    deinit {
        if let observation {
            let download = download
            SongDownload.queue.async { download.stopObserving(observation) }
        }
        if hasReachSession {
            reachSession.invalidateAndCancel()
        }
        let released = released
        Task { @MainActor in released() }
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        requests.append(loadingRequest)
        serve()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        requests.removeAll { $0 === loadingRequest }
        for (id, request) in reaches where request === loadingRequest {
            reaches[id] = nil
            reachSession.getAllTasks { tasks in tasks.first { $0.taskIdentifier == id }?.cancel() }
        }
    }

    // MARK: - Answering

    /// Answers whatever the file can now answer.
    private func serve() {
        for request in requests where !request.isFinished && !request.isCancelled {
            serve(request)
        }
        requests.removeAll { $0.isFinished || $0.isCancelled }
    }

    private func serve(_ request: AVAssetResourceLoadingRequest) {
        if let failure = download.failure {
            request.finishLoading(with: failure)
            return
        }
        // Nothing can be answered until the server has said how long the
        // file is.
        guard let length = download.expectedLength else { return }
        if let info = request.contentInformationRequest {
            info.contentType = contentType
            info.contentLength = length
            info.isByteRangeAccessSupported = true
        }
        guard let data = request.dataRequest else {
            request.finishLoading()
            return
        }
        guard !reaches.values.contains(where: { $0 === request }) else { return }
        let end = data.requestsAllDataToEndOfResource
            ? length
            : min(length, data.requestedOffset + Int64(data.requestedLength))
        let available = download.isFinished ? length : download.written
        if data.currentOffset > available + Self.reachAhead {
            reach(for: request, from: data.currentOffset, to: end)
            return
        }
        while data.currentOffset < min(end, available),
              let bytes = download.read(at: data.currentOffset, length: Int(min(Int64(Self.chunk), end - data.currentOffset))),
              !bytes.isEmpty {
            data.respond(with: bytes)
        }
        if data.currentOffset >= end {
            request.finishLoading()
        }
    }

    /// What the file is, for the player: by the server's word, else by its
    /// extension.
    private var contentType: String {
        download.mimeType.flatMap { UTType(mimeType: $0)?.identifier }
            ?? UTType(filenameExtension: download.fileExtension)?.identifier
            ?? UTType.audio.identifier
    }

    // MARK: - Reaching ahead

    private func reach(for request: AVAssetResourceLoadingRequest, from start: Int64, to end: Int64) {
        var fetch = URLRequest(url: remote)
        fetch.setValue("bytes=\(start)-\(end - 1)", forHTTPHeaderField: "Range")
        hasReachSession = true
        SongDownload.log.notice("song download \(self.download.key, privacy: .public): reaching ahead to \(start) of \(end), \(self.download.written) in")
        let task = reachSession.dataTask(with: fetch)
        reaches[task.taskIdentifier] = request
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Only a range will do: the whole file from the top would be
        // answered at the wrong place.
        guard reaches[dataTask.taskIdentifier] != nil, (response as? HTTPURLResponse)?.statusCode == 206 else {
            reaches[dataTask.taskIdentifier]?.finishLoading(with: URLError(.badServerResponse))
            reaches[dataTask.taskIdentifier] = nil
            return completionHandler(.cancel)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        reaches[dataTask.taskIdentifier]?.dataRequest?.respond(with: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let request = reaches.removeValue(forKey: task.taskIdentifier), !request.isCancelled else { return }
        if let error {
            request.finishLoading(with: error)
        } else {
            request.finishLoading()
        }
        requests.removeAll { $0 === request }
    }
}

/// Hands a session's data callbacks to a target it doesn't keep alive.
private final class WeakDataDelegate: NSObject, URLSessionDataDelegate {
    private weak var target: (NSObject & URLSessionDataDelegate)?

    init(_ target: NSObject & URLSessionDataDelegate) {
        self.target = target
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let target else { return completionHandler(.cancel) }
        target.urlSession?(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        target?.urlSession?(session, dataTask: dataTask, didReceive: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        target?.urlSession?(session, task: task, didCompleteWithError: error)
    }
}
