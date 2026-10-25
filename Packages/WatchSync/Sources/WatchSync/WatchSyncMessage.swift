import Foundation

/// What crosses WatchConnectivity: each side's application context — only
/// the latest matters, the system keeps it for an app that isn't running,
/// and it works between simulators. The iPhone's carries the picks, the
/// places in the books among them (`WatchBookPlaces`), its sign-ins
/// (`WatchCredentials`) and the watch's share of the free downloads
/// (`WatchAllowance`); the watch's carries the picks and places as it has
/// them, and what it holds against that share (`WatchHeldDownloads`).
/// Each side merges what arrives (`WatchPicks.merged`,
/// `WatchBookPlaces.merged`). The picks and places travel packed, with a
/// `sentAt` stamp so sending them again always counts as a change.
///
/// Messages go the other way, with a reply: the watch asking for the
/// sign-ins afresh (`credentialsRequest`), when the Audiobookshelf token it
/// was lent is about to run out — the iPhone renews its own and answers
/// with the context's sign-ins (`credentialsReply`) — and asking what the
/// iPhone plays (`nowPlayingRequest`) or to play, pause or skip it
/// (`commandRequest`), answered with what it plays then; and asking for the
/// queue it plays from (`queueRequest`, answered with `queueMessage`) or to
/// play a song in it (`playQueueRequest`, answered as a press is). While the
/// watch app is open the iPhone also sends what it plays unasked, as it
/// changes (`nowPlayingMessage`).
public enum WatchSyncMessage {
    public static let picksKey = "picks"
    public static let placesKey = "places"
    public static let credentialsKey = "credentials"
    public static let sentAtKey = "sentAt"
    public static let requestKey = "request"
    public static let nowPlayingKey = "nowPlaying"
    public static let queueKey = "queue"
    public static let positionKey = "position"
    public static let allowanceKey = "allowance"
    public static let heldKey = "held"

    public static func context(
        picks: WatchPicks,
        places: WatchBookPlaces? = nil,
        credentials: WatchCredentials? = nil,
        allowance: WatchAllowance? = nil,
        held: WatchHeldDownloads? = nil,
        sentAt: Date = .now
    ) throws -> [String: Any] {
        var context: [String: Any] = [
            picksKey: pack(try picks.encoded()),
            sentAtKey: sentAt.timeIntervalSince1970,
        ]
        if let places {
            context[placesKey] = pack(try places.encoded())
        }
        if let credentials {
            context[credentialsKey] = try JSONEncoder().encode(credentials)
        }
        if let allowance {
            context[allowanceKey] = try JSONEncoder().encode(allowance)
        }
        if let held {
            context[heldKey] = try JSONEncoder().encode(held)
        }
        return context
    }

    public static func picks(in context: [String: Any]) -> WatchPicks? {
        guard let packed = context[picksKey] as? Data, let data = unpack(packed) else { return nil }
        return try? WatchPicks.decoded(from: data)
    }

    public static func places(in context: [String: Any]) -> WatchBookPlaces? {
        guard let packed = context[placesKey] as? Data, let data = unpack(packed) else { return nil }
        return try? WatchBookPlaces.decoded(from: data)
    }

    public static func credentials(in context: [String: Any]) -> WatchCredentials? {
        guard let data = context[credentialsKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchCredentials.self, from: data)
    }

    /// The iPhone's word on the watch's share; nil from an iPhone a version
    /// behind.
    public static func allowance(in context: [String: Any]) -> WatchAllowance? {
        guard let data = context[allowanceKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchAllowance.self, from: data)
    }

    /// What the watch holds against its share; nil from a watch a version
    /// behind.
    public static func held(in context: [String: Any]) -> WatchHeldDownloads? {
        guard let data = context[heldKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchHeldDownloads.self, from: data)
    }

    // MARK: - Asking for the sign-ins

    /// The watch's message asking for fresh sign-ins.
    public static var credentialsRequest: [String: Any] { [requestKey: "credentials"] }

    public static func isCredentialsRequest(_ message: [String: Any]) -> Bool {
        message[requestKey] as? String == "credentials"
    }

    /// The iPhone's answer: the sign-ins, read back with `credentials(in:)`.
    public static func credentialsReply(_ credentials: WatchCredentials) throws -> [String: Any] {
        [credentialsKey: try JSONEncoder().encode(credentials)]
    }

    // MARK: - What the iPhone plays

    /// The watch asking what the iPhone plays.
    public static var nowPlayingRequest: [String: Any] { [requestKey: "nowPlaying"] }

    /// The watch asking the iPhone to play or pause.
    public static var togglePlayPauseRequest: [String: Any] { commandRequest(.togglePlayPause) }

    /// The watch asking the iPhone to play or pause, or to skip.
    public static func commandRequest(_ command: WatchPhoneCommand) -> [String: Any] {
        [requestKey: command.rawValue]
    }

    public static func isNowPlayingRequest(_ message: [String: Any]) -> Bool {
        message[requestKey] as? String == "nowPlaying"
    }

    public static func isTogglePlayPauseRequest(_ message: [String: Any]) -> Bool {
        command(in: message) == .togglePlayPause
    }

    /// The press a request asks the iPhone to carry out, nil for any other
    /// message.
    public static func command(in message: [String: Any]) -> WatchPhoneCommand? {
        (message[requestKey] as? String).flatMap(WatchPhoneCommand.init(rawValue:))
    }

    /// What the iPhone plays, nil for nothing: sent unasked, and as the
    /// answer to every request about it.
    public static func nowPlayingMessage(_ nowPlaying: WatchPhoneNowPlaying?) throws -> [String: Any] {
        [nowPlayingKey: try nowPlaying.map { try JSONEncoder().encode($0) } ?? Data()]
    }

    /// Whether a message says what the iPhone plays, nothing included.
    public static func carriesNowPlaying(_ message: [String: Any]) -> Bool {
        message[nowPlayingKey] is Data
    }

    public static func nowPlaying(in message: [String: Any]) -> WatchPhoneNowPlaying? {
        guard let data = message[nowPlayingKey] as? Data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(WatchPhoneNowPlaying.self, from: data)
    }

    // MARK: - The iPhone's queue

    /// The watch asking for the queue the iPhone plays from.
    public static var queueRequest: [String: Any] { [requestKey: "queue"] }

    public static func isQueueRequest(_ message: [String: Any]) -> Bool {
        message[requestKey] as? String == "queue"
    }

    /// The watch asking the iPhone to play the song at `position` (from 1)
    /// in its queue.
    public static func playQueueRequest(at position: Int) -> [String: Any] {
        [requestKey: "playQueue", positionKey: position]
    }

    /// The position a request asks the iPhone to play, nil for any other
    /// message.
    public static func queuePositionToPlay(in message: [String: Any]) -> Int? {
        guard message[requestKey] as? String == "playQueue", let position = message[positionKey] as? Int, position > 0 else { return nil }
        return position
    }

    /// The queue, empty for none: the answer to `queueRequest`.
    public static func queueMessage(_ queue: WatchPhoneQueue) throws -> [String: Any] {
        [queueKey: try JSONEncoder().encode(queue)]
    }

    /// The queue a message carries; nil for any other message, an iPhone
    /// a version behind answering with nothing among them.
    public static func queue(in message: [String: Any]) -> WatchPhoneQueue? {
        guard let data = message[queueKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchPhoneQueue.self, from: data)
    }

    // MARK: - Packing

    private enum Packing: UInt8 {
        case plain = 0
        case lzfse = 1
    }

    /// JSON is mostly repeated URLs, so it shrinks several times over.
    /// LZFSE where the system has it; plain elsewhere (the Linux test runs).
    /// A leading byte says which.
    static func pack(_ data: Data) -> Data {
        #if canImport(Darwin)
        if let compressed = try? (data as NSData).compressed(using: .lzfse) as Data {
            return Data([Packing.lzfse.rawValue]) + compressed
        }
        #endif
        return Data([Packing.plain.rawValue]) + data
    }

    static func unpack(_ packed: Data) -> Data? {
        guard let first = packed.first, let packing = Packing(rawValue: first) else { return nil }
        let body = packed.dropFirst()
        switch packing {
        case .plain:
            return Data(body)
        case .lzfse:
            #if canImport(Darwin)
            return try? (Data(body) as NSData).decompressed(using: .lzfse) as Data
            #else
            return nil
            #endif
        }
    }
}
