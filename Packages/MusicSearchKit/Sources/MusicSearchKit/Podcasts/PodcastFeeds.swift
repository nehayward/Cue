import Foundation
import Observation
import os

/// The podcasts followed by their feeds, kept on this device: no account,
/// no server of the listener's. Each episode's audio is a plain URL, so
/// this device plays it and a speaker fetches the same address
/// (`DirectStreamProvider`), and the book player plays an episode as a
/// book of one file, keeping its place.
///
/// Feeds are read when followed and again when they're looked at, at most
/// every `refreshInterval`. Kept in Application Support (Podcasts.json),
/// with each episode's audio address by its id for `streamURL(for:)`, which
/// is asked from any thread.
@Observable
public final class PodcastFeeds: DirectStreamProvider {
    public static let shared = PodcastFeeds()

    /// What's followed, by title.
    public private(set) var feeds: [PodcastFeed] = []
    /// A read of every feed is under way.
    public private(set) var isRefreshing = false

    @ObservationIgnored private let session: URLSession

    /// How long a feed's read stands before it's read again.
    public static let refreshInterval: TimeInterval = 60 * 60

    public init(session: URLSession = .shared) {
        self.session = session
        feeds = Self.readStored()
        Self.index(feeds)
    }

    public func feed(id: String) -> PodcastFeed? {
        feeds.first { $0.id == id }
    }

    /// An episode by its id, or its audio's.
    public func episode(id: String) -> PodcastEpisode? {
        episodeWithFeed(id: id)?.0
    }

    /// The feed an episode is in, with the episode, by the episode's id or
    /// its audio's.
    public func episodeWithFeed(id: String) -> (PodcastEpisode, PodcastFeed)? {
        let episodeID = PodcastIDs.episodeID(ofPart: id)
        let feedID = String(episodeID.prefix { $0 != PodcastIDs.separator })
        guard let feed = feed(id: feedID), let episode = feed.episodes.first(where: { $0.id == episodeID }) else { return nil }
        return (episode, feed)
    }

    public func isFollowing(_ url: URL) -> Bool {
        let id = PodcastFeed.id(for: url)
        return feeds.contains { $0.id == id }
    }

    // MARK: - Following

    public enum FollowError: Error, Equatable, Sendable {
        case unreachable(String)
        case notAFeed

        public var message: String {
            switch self {
            case let .unreachable(message): message
            case .notAFeed: "That address isn't a podcast feed. Check it's the feed's (RSS) address, not the podcast's web page."
            }
        }
    }

    /// Reads a feed without following it, for a podcast's page before it's
    /// followed.
    public func preview(_ url: URL) async -> Result<PodcastFeed, FollowError> {
        await read(url)
    }

    /// Follows the feed at `url` (`feed://` and bare addresses taken as
    /// `https`), reading it first: one that isn't a feed isn't followed.
    @MainActor
    @discardableResult
    public func follow(_ url: URL) async -> Result<PodcastFeed, FollowError> {
        let result = await read(Self.normalized(url))
        if case let .success(feed) = result {
            keep(feed)
        }
        return result
    }

    @MainActor
    public func unfollow(_ feed: PodcastFeed) {
        feeds.removeAll { $0.id == feed.id }
        save()
    }

    /// Reads every feed followed whose last read is older than
    /// `refreshInterval`, or all of them with `force`, a few at a time.
    @MainActor
    public func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        let due = feeds.filter { force || Date.now.timeIntervalSince($0.checkedAt ?? .distantPast) > Self.refreshInterval }
        guard !due.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        // Each read with the id it was followed under: a feed that moved
        // comes back under another.
        let reads = await withTaskGroup(of: (String, PodcastFeed)?.self) { group -> [(String, PodcastFeed)] in
            var reads: [(String, PodcastFeed)] = []
            for (index, feed) in due.enumerated() {
                if index >= 4, let done = await group.next(), let done {
                    reads.append(done)
                }
                group.addTask { [self] in
                    guard case let .success(read) = await self.read(feed.url) else { return nil }
                    return (feed.id, read)
                }
            }
            for await done in group {
                if let done { reads.append(done) }
            }
            return reads
        }
        for (oldID, read) in reads {
            keep(read, replacing: oldID)
        }
    }

    /// Reads one feed again now.
    @MainActor
    @discardableResult
    public func refresh(_ feed: PodcastFeed) async -> PodcastFeed? {
        guard case let .success(read) = await read(feed.url) else { return nil }
        keep(read, replacing: feed.id)
        return read
    }

    /// Keeps a read, in the place of the feed it is (or `replacing`, the
    /// one it was before it moved), by title.
    @MainActor
    private func keep(_ feed: PodcastFeed, replacing oldID: String? = nil) {
        var all = feeds.filter { $0.id != feed.id && $0.id != oldID }
        all.append(feed)
        feeds = all.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        save()
    }

    private func read(_ url: URL) async -> Result<PodcastFeed, FollowError> {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Cue", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failure(.unreachable("The feed's server answered \(http.statusCode)."))
            }
            // Followed at the address it was asked by: a feed that moved
            // says so itself (`itunes:new-feed-url`).
            guard let feed = PodcastFeedParser.parse(data, url: url) else { return .failure(.notAFeed) }
            return .success(feed)
        } catch {
            return .failure(.unreachable("Couldn't reach the feed. Check the address and your connection."))
        }
    }

    /// `feed://`, `podcast://` and a bare host as the `https` address they
    /// stand for.
    public static func normalized(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        switch components.scheme?.lowercased() {
        case "feed", "podcast", "pcast", "itpc":
            components.scheme = "https"
        case nil:
            return URL(string: "https://\(url.absoluteString)") ?? url
        default:
            break
        }
        return components.url ?? url
    }

    /// An address as typed or pasted, if it can be a feed's.
    public static func feedURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)"),
              let host = url.host(), host.contains(".") else { return nil }
        return normalized(url)
    }

    // MARK: - Finding podcasts

    /// A podcast found in Apple's podcast directory, with its feed.
    public struct SearchResult: Hashable, Sendable, Identifiable {
        public let title: String
        public let author: String?
        public let artworkURL: URL?
        public let feedURL: URL
        public let episodeCount: Int?
        public var id: String { feedURL.absoluteString }
    }

    private struct DirectoryAnswer: Decodable {
        struct Podcast: Decodable {
            let collectionName: String?
            let artistName: String?
            let feedUrl: String?
            let artworkUrl600: String?
            let trackCount: Int?
        }
        let results: [Podcast]
    }

    /// Podcasts matching `term` in Apple's podcast directory (the iTunes
    /// Search API, which needs no key): its feeds are the podcasts' own.
    public func search(_ term: String) async -> [SearchResult]? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "term", value: term)
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, _) = try? await session.data(for: request),
              let answer = try? JSONDecoder().decode(DirectoryAnswer.self, from: data) else { return nil }
        return answer.results.compactMap { podcast in
            guard let feed = podcast.feedUrl.flatMap({ URL(string: $0) }), let title = podcast.collectionName else { return nil }
            return SearchResult(
                title: title,
                author: podcast.artistName,
                artworkURL: podcast.artworkUrl600.flatMap { URL(string: $0) },
                feedURL: feed,
                episodeCount: podcast.trackCount
            )
        }
    }

    // MARK: - Streams

    /// Each episode's audio by its id, and its id by its audio's address, for
    /// what's asked from any thread: a speaker's queue row, a stream URL.
    private static let addresses = OSAllocatedUnfairLock(initialState: (byID: [String: URL](), byURL: [String: String]()))

    static func index(_ feeds: [PodcastFeed]) {
        var byID: [String: URL] = [:]
        var byURL: [String: String] = [:]
        for episode in feeds.flatMap(\.episodes) {
            byID[episode.id] = episode.audioURL
            byID[episode.partID] = episode.audioURL
            // A speaker's row is the audio, the track the book plays.
            let address = episode.audioURL.absoluteString
            byURL[address] = episode.partID
            // As the row reads once its percent-encoding is undone.
            if let decoded = address.removingPercentEncoding, decoded != address {
                byURL[decoded] = episode.partID
            }
        }
        addresses.withLock { $0 = (byID, byURL) }
    }

    /// An episode's audio: the feed's own address for it, which needs no
    /// sign-in, so this device and a speaker play the same. The extension
    /// and the destination change nothing: it's never converted.
    public static func streamURL(for id: String, fileExtension: String?, destination: StreamTranscoding.Destination?) -> URL? {
        addresses.withLock { $0.byID[id] }
    }

    /// The episode audio a stream address plays (its `partID`), read back
    /// off a speaker's queue.
    public static func episodeID(forStreamURL raw: String) -> String? {
        // As set, or as the speaker hands it back: entities in the query
        // unescaped, or percent-encoding undone.
        let candidates = [raw, raw.replacingOccurrences(of: "&amp;", with: "&"), raw.removingPercentEncoding ?? raw]
        return addresses.withLock { addresses in
            for candidate in candidates {
                if let id = addresses.byURL[candidate] { return id }
            }
            return nil
        }
    }

    /// Whether a speaker's stream is a followed podcast's episode.
    public static func isStreamURL(_ raw: String) -> Bool {
        episodeID(forStreamURL: raw) != nil
    }

    // MARK: - Storage

    private static let log = Logger(subsystem: "dance.cue", category: "podcasts")

    @MainActor
    private func save() {
        let feeds = feeds
        Self.index(feeds)
        Task.detached(priority: .utility) {
            guard let url = Self.fileURL, let data = try? JSONEncoder().encode(feeds) else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                Self.log.error("couldn't keep the podcasts: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static var fileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("Podcasts.json")
    }

    private static func readStored() -> [PodcastFeed] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PodcastFeed].self, from: data)) ?? []
    }
}
