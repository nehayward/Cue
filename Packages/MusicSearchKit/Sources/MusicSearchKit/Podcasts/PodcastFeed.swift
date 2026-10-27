import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A podcast followed by its feed (RSS, with Apple's `itunes:` tags): what
/// it is and its episodes, newest first. No account and no server: the
/// feed is the podcast, and each episode's audio is a plain URL that this
/// device and a speaker both play (`PodcastFeeds`).
public struct PodcastFeed: Codable, Sendable, Hashable, Identifiable {
    /// The feed's address, as followed (after any redirect the feed's own
    /// `itunes:new-feed-url` asked for).
    public var url: URL
    public var title: String
    public var author: String?
    public var summary: String?
    public var artworkURL: URL?
    /// Newest first.
    public var episodes: [PodcastEpisode]
    /// When the feed was last read.
    public var checkedAt: Date?

    public var id: String { Self.id(for: url) }

    public init(url: URL, title: String, author: String? = nil, summary: String? = nil, artworkURL: URL? = nil, episodes: [PodcastEpisode] = [], checkedAt: Date? = nil) {
        self.url = url
        self.title = title
        self.author = author
        self.summary = summary
        self.artworkURL = artworkURL
        self.episodes = episodes
        self.checkedAt = checkedAt
    }

    /// A feed's id: a short hash of its address, the same on every device.
    public static func id(for url: URL) -> String {
        PodcastIDs.hash(url.absoluteString)
    }
}

/// One episode in a feed.
public struct PodcastEpisode: Codable, Sendable, Hashable, Identifiable {
    /// `<feed id>~<hash of its guid>`: what Cue calls it everywhere, a
    /// book of one file in the book player.
    public var id: String
    public var title: String
    public var summary: String?
    public var published: Date?
    /// Seconds, as the feed says (`itunes:duration`); nil when it doesn't.
    public var duration: TimeInterval?
    /// The audio itself (the feed's `enclosure`).
    public var audioURL: URL
    public var mimeType: String?
    /// The episode's own picture, else the podcast's.
    public var artworkURL: URL?

    public var feedID: String {
        String(id.prefix { $0 != PodcastIDs.separator })
    }

    /// Its audio's id, as the track the player plays: apart from the
    /// episode's own, which is the book's.
    public var partID: String { PodcastIDs.partID(ofEpisode: id) }

    /// The audio's extension, for a speaker's hint and a download's name:
    /// the URL's, else what its type says.
    public var fileExtension: String? {
        let ext = audioURL.pathExtension.lowercased()
        if !ext.isEmpty, ext.count <= 4 { return ext }
        switch mimeType?.lowercased() {
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/mp4", "audio/x-m4a", "audio/aac", "audio/m4a": return "m4a"
        case "audio/ogg": return "ogg"
        case "audio/opus": return "opus"
        default: return nil
        }
    }
}

/// The ids Cue makes for feeds and episodes.
public enum PodcastIDs {
    /// Between a feed's id and an episode's own in an episode's id.
    public static let separator: Character = "~"

    public static func episodeID(feedID: String, guid: String) -> String {
        "\(feedID)\(separator)\(hash(guid))"
    }

    private static let partSuffix = "\(separator)audio"

    /// The id of an episode's audio, the track a book of one file plays.
    public static func partID(ofEpisode id: String) -> String {
        id + partSuffix
    }

    /// The episode an audio's id is of, or the id itself for an episode's.
    public static func episodeID(ofPart id: String) -> String {
        id.hasSuffix(partSuffix) ? String(id.dropLast(partSuffix.count)) : id
    }

    /// FNV-1a, 64 bits, as hex: stable across launches and devices, unlike
    /// `hashValue`, and short enough for a file name.
    static func hash(_ text: String) -> String {
        var value: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x100000001b3
        }
        return String(value, radix: 16)
    }
}

/// Reads a feed: the channel's title, author, summary and picture, and each
/// item with audio as an episode. Items without an audio enclosure (a blog
/// post, a video) are left out.
public enum PodcastFeedParser {
    public static func parse(_ data: Data, url: URL) -> PodcastFeed? {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = reader
        guard parser.parse() || reader.sawChannel, reader.sawChannel else { return nil }
        let feedID = PodcastFeed.id(for: url)
        let artwork = reader.channelImage.flatMap { URL(string: $0) }
        var seen = Set<String>()
        let episodes: [PodcastEpisode] = reader.items.compactMap { item in
            guard let enclosure = item.enclosureURL.flatMap({ URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
                  isAudio(type: item.enclosureType, url: enclosure) else { return nil }
            let guid = item.guid?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? enclosure.absoluteString
            let id = PodcastIDs.episodeID(feedID: feedID, guid: guid)
            guard seen.insert(id).inserted else { return nil }
            return PodcastEpisode(
                id: id,
                title: item.title?.trimmed.nilIfEmpty ?? "Episode",
                summary: (item.summary ?? item.description)?.trimmed.nilIfEmpty,
                published: item.pubDate.flatMap(date(from:)),
                duration: item.duration.flatMap(duration(from:)),
                audioURL: enclosure,
                mimeType: item.enclosureType,
                artworkURL: item.image.flatMap { URL(string: $0) } ?? artwork
            )
        }
        .sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
        return PodcastFeed(
            url: reader.newFeedURL.flatMap { URL(string: $0.trimmed) } ?? url,
            title: reader.channelTitle?.trimmed.nilIfEmpty ?? url.host() ?? "Podcast",
            author: reader.channelAuthor?.trimmed.nilIfEmpty,
            summary: (reader.channelSummary ?? reader.channelDescription)?.trimmed.nilIfEmpty,
            artworkURL: artwork,
            episodes: episodes,
            checkedAt: .now
        )
    }

    private static func isAudio(type: String?, url: URL) -> Bool {
        if let type = type?.lowercased(), !type.isEmpty {
            return type.hasPrefix("audio/")
        }
        return ["mp3", "m4a", "aac", "ogg", "opus", "wav", "flac", "mp4"].contains(url.pathExtension.lowercased())
    }

    /// `itunes:duration`: seconds, `MM:SS` or `HH:MM:SS`.
    static func duration(from text: String) -> TimeInterval? {
        let parts = text.trimmed.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        let seconds = parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
        return seconds > 0 ? seconds : nil
    }

    private static let dateFormats = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm Z",
        "dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy",
        "yyyy-MM-dd'T'HH:mm:ssZ",
    ]

    /// RSS's dates (RFC 822, as feeds write it), and the odd ISO 8601 one.
    static func date(from text: String) -> Date? {
        let text = text.trimmed
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private final class Reader: NSObject, XMLParserDelegate {
        struct Item {
            var title: String?
            var guid: String?
            var description: String?
            var summary: String?
            var pubDate: String?
            var duration: String?
            var enclosureURL: String?
            var enclosureType: String?
            var image: String?
        }

        var sawChannel = false
        var channelTitle: String?
        var channelAuthor: String?
        var channelSummary: String?
        var channelDescription: String?
        var channelImage: String?
        var newFeedURL: String?
        var items: [Item] = []

        private var item: Item?
        private var text = ""
        /// The elements open, innermost last: a channel's `image` holds a
        /// `title` and `url` of its own.
        private var path: [String] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            path.append(name)
            text = ""
            switch name {
            case "channel":
                sawChannel = true
            case "item":
                item = Item()
            case "enclosure":
                // The first audio enclosure: some items carry a video too.
                if item?.enclosureURL == nil || (item?.enclosureType?.hasPrefix("audio/") != true && attributes["type"]?.hasPrefix("audio/") == true) {
                    item?.enclosureURL = attributes["url"]
                    item?.enclosureType = attributes["type"]
                }
            case "itunes:image":
                if let href = attributes["href"] {
                    if item != nil {
                        item?.image = href
                    } else {
                        channelImage = href
                    }
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, foundCDATA block: Data) {
            text += String(decoding: block, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            defer {
                if !path.isEmpty { path.removeLast() }
                text = ""
            }
            let parent = path.count >= 2 ? path[path.count - 2] : nil
            if item != nil {
                switch name {
                case "item":
                    if let item { items.append(item) }
                    item = nil
                case "title" where parent == "item":
                    item?.title = text
                case "guid":
                    item?.guid = text
                case "description" where parent == "item":
                    item?.description = text
                case "itunes:summary", "content:encoded":
                    if item?.summary == nil { item?.summary = text }
                case "pubDate":
                    item?.pubDate = text
                case "itunes:duration":
                    item?.duration = text
                default:
                    break
                }
                return
            }
            switch name {
            case "title" where parent == "channel":
                channelTitle = text
            case "itunes:author" where parent == "channel":
                channelAuthor = text
            case "itunes:summary" where parent == "channel":
                channelSummary = text
            case "description" where parent == "channel":
                channelDescription = text
            case "url" where parent == "image" && channelImage == nil:
                channelImage = text.trimmed
            case "itunes:new-feed-url":
                newFeedURL = text
            default:
                break
            }
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
