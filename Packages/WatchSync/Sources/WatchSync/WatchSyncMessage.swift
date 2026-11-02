import Foundation

/// What crosses WatchConnectivity: each side's application context — only
/// the latest matters, the system keeps it for an app that isn't running,
/// and it works between simulators. The iPhone's carries the picks, the
/// places in the books among them (`WatchBookPlaces`), its sign-ins
/// (`WatchCredentials`) and the watch's share of the free downloads
/// (`WatchAllowance`) and what it plays (`WatchPhoneNowPlaying`, without its
/// cover), for the watch app to show the moment it opens; the watch's
/// carries the picks and places as it has them, and what it holds against
/// that share (`WatchHeldDownloads`).
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
/// play a song in it (`playQueueRequest`, answered as a press is); for the
/// chapters of the book it plays (`chaptersRequest`, answered with
/// `chaptersMessage`), to play one (`playChapterRequest`), to set its sleep
/// timer (`sleepTimerRequest`) or a book's speed (`speedRequest`), to play
/// one of the watch's books there (`playBookRequest`) or an album, playlist,
/// artist or song from its library (`playItemRequest`), or to move what it
/// plays to another route (`switchRouteRequest`), each answered with what it
/// plays then; and for the routes there are (`routesRequest`, answered with
/// `routesMessage`). While the watch app is open the iPhone also
/// sends what it plays unasked, as it changes (`nowPlayingMessage`).
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
    public static let chaptersKey = "chapters"
    public static let chapterKey = "chapter"
    public static let sleepKey = "sleep"
    public static let rateKey = "rate"
    public static let pickKey = "pick"
    public static let placeKey = "place"
    public static let targetKey = "target"
    public static let timeKey = "time"
    public static let routesKey = "routes"
    public static let routeKey = "route"
    public static let songKey = "song"
    public static let shuffleKey = "shuffle"

    public static func context(
        picks: WatchPicks,
        places: WatchBookPlaces? = nil,
        credentials: WatchCredentials? = nil,
        allowance: WatchAllowance? = nil,
        held: WatchHeldDownloads? = nil,
        nowPlaying: Data? = nil,
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
        if let nowPlaying {
            context[nowPlayingKey] = nowPlaying
        }
        return context
    }

    /// When a context was sent.
    public static func sentAt(in context: [String: Any]) -> Date? {
        (context[sentAtKey] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
    }

    /// What the iPhone plays, as its context carries it (`context`'s
    /// `nowPlaying`, read back with `nowPlaying(in:)`): empty for nothing.
    public static func nowPlayingCard(_ nowPlaying: WatchPhoneNowPlaying?) throws -> Data {
        try nowPlaying.map { try JSONEncoder().encode($0) } ?? Data()
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

    // MARK: - The iPhone's book

    /// The watch asking for the chapters of the book the iPhone plays.
    public static var chaptersRequest: [String: Any] { [requestKey: "chapters"] }

    public static func isChaptersRequest(_ message: [String: Any]) -> Bool {
        message[requestKey] as? String == "chapters"
    }

    /// The chapters, none for a book without (or nothing playing): the
    /// answer to `chaptersRequest`.
    public static func chaptersMessage(_ chapters: WatchPhoneChapters) throws -> [String: Any] {
        [chaptersKey: try JSONEncoder().encode(chapters)]
    }

    /// The chapters a message carries; nil for any other message.
    public static func chapters(in message: [String: Any]) -> WatchPhoneChapters? {
        guard let data = message[chaptersKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchPhoneChapters.self, from: data)
    }

    /// The watch asking the iPhone to play its book from a chapter's start
    /// (`WatchPhoneChapters.Chapter.id`).
    public static func playChapterRequest(_ id: Int) -> [String: Any] {
        [requestKey: "playChapter", chapterKey: id]
    }

    /// The chapter a request asks the iPhone to play, nil for any other
    /// message.
    public static func chapterToPlay(in message: [String: Any]) -> Int? {
        guard message[requestKey] as? String == "playChapter", let id = message[chapterKey] as? Int, id >= 0 else { return nil }
        return id
    }

    /// The watch setting the sleep timer of what the iPhone plays.
    public static func sleepTimerRequest(_ sleep: WatchPhoneSleep) -> [String: Any] {
        [requestKey: "sleepTimer", sleepKey: (try? JSONEncoder().encode(sleep)) ?? Data()]
    }

    /// The sleep timer a request asks for, nil for any other message.
    public static func sleepTimer(in message: [String: Any]) -> WatchPhoneSleep? {
        guard message[requestKey] as? String == "sleepTimer", let data = message[sleepKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchPhoneSleep.self, from: data)
    }

    /// The watch setting the speed of the book the iPhone plays.
    public static func speedRequest(_ rate: Double) -> [String: Any] {
        [requestKey: "speed", rateKey: rate]
    }

    /// The speed a request asks for, nil for any other message.
    public static func speed(in message: [String: Any]) -> Double? {
        guard message[requestKey] as? String == "speed", let rate = message[rateKey] as? Double, rate > 0 else { return nil }
        return rate
    }

    /// The watch asking the iPhone to play one of its books, on `target`:
    /// from `time` (book time), or from its place — the watch's, `place`,
    /// when that's newer than the iPhone's.
    public static func playBookRequest(_ pick: WatchPick, place: WatchBookPlace?, from time: Double? = nil, on target: WatchPhoneTarget) throws -> [String: Any] {
        var request: [String: Any] = [
            requestKey: "playBook",
            pickKey: try JSONEncoder().encode(pick),
            targetKey: target.key,
        ]
        if let place {
            request[placeKey] = try JSONEncoder().encode(place)
        }
        if let time {
            request[timeKey] = time
        }
        return request
    }

    /// What a request asks the iPhone to play; nil for any other message.
    public static func bookToPlay(in message: [String: Any]) -> (pick: WatchPick, place: WatchBookPlace?, time: Double?, target: WatchPhoneTarget)? {
        guard message[requestKey] as? String == "playBook",
              let data = message[pickKey] as? Data,
              let pick = try? JSONDecoder().decode(WatchPick.self, from: data) else { return nil }
        let place = (message[placeKey] as? Data).flatMap { try? JSONDecoder().decode(WatchBookPlace.self, from: $0) }
        let target = (message[targetKey] as? String).flatMap(WatchPhoneTarget.init(key:)) ?? .route
        return (pick, place, message[timeKey] as? Double, target)
    }

    // MARK: - The iPhone playing the watch's music

    /// The watch asking the iPhone to play an album, playlist, artist or
    /// song from its library, on `target`: from the song `songID` in it
    /// (the id its server gives it), or shuffled.
    public static func playItemRequest(_ pick: WatchPick, from songID: String? = nil, shuffled: Bool = false, on target: WatchPhoneTarget) throws -> [String: Any] {
        var request: [String: Any] = [
            requestKey: "playItem",
            pickKey: try JSONEncoder().encode(pick),
            targetKey: target.key,
            shuffleKey: shuffled,
        ]
        if let songID {
            request[songKey] = songID
        }
        return request
    }

    /// What a request asks the iPhone to play; nil for any other message.
    public static func itemToPlay(in message: [String: Any]) -> (pick: WatchPick, songID: String?, shuffled: Bool, target: WatchPhoneTarget)? {
        guard message[requestKey] as? String == "playItem",
              let data = message[pickKey] as? Data,
              let pick = try? JSONDecoder().decode(WatchPick.self, from: data) else { return nil }
        let target = (message[targetKey] as? String).flatMap(WatchPhoneTarget.init(key:)) ?? .route
        return (pick, message[songKey] as? String, message[shuffleKey] as? Bool ?? false, target)
    }

    // MARK: - Where the iPhone plays

    /// The watch asking where the iPhone can play.
    public static var routesRequest: [String: Any] { [requestKey: "routes"] }

    public static func isRoutesRequest(_ message: [String: Any]) -> Bool {
        message[requestKey] as? String == "routes"
    }

    /// The routes: the answer to `routesRequest`.
    public static func routesMessage(_ routes: WatchPhoneRoutes) throws -> [String: Any] {
        [routesKey: try JSONEncoder().encode(routes)]
    }

    /// The routes a message carries; nil for any other message.
    public static func routes(in message: [String: Any]) -> WatchPhoneRoutes? {
        guard let data = message[routesKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchPhoneRoutes.self, from: data)
    }

    /// The watch moving what the iPhone plays to another of its routes
    /// (`WatchPhoneRoutes.Route.id`), as its Play On does.
    public static func switchRouteRequest(to id: String) -> [String: Any] {
        [requestKey: "switchRoute", routeKey: id]
    }

    /// The route a request asks the iPhone to move to, nil for any other
    /// message.
    public static func routeToSwitch(in message: [String: Any]) -> String? {
        guard message[requestKey] as? String == "switchRoute", let id = message[routeKey] as? String, !id.isEmpty else { return nil }
        return id
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
