import Foundation

/// The addresses Cue builds for an Audiobookshelf server, worked out from
/// what they're made of, so they can be built anywhere — `PlayableContent`
/// asks for a file's URL from any thread.
///
/// A speaker fetches what it's handed with no headers, so a file's URL has
/// to carry what lets it in. Two kinds do:
/// - a listening session's track (`/public/session/<id>/track/<index>`,
///   servers 2.22 and later), open to anyone with the session's id for as
///   long as the session lives — what the server's own apps play, and the
///   first choice;
/// - the file itself (`/api/items/<id>/file/<ino>`) with the access token
///   in the query, for when there's no session: good for the token's life
///   (an hour on current servers), so only a stopgap.
///
/// Both end in an extension hint (`ext=.m4a`) the server ignores: Sonos
/// sorts plain-HTTP queue items by the extension it finds in the URL and
/// turns away those without one.
public enum AudiobookshelfURLs {
    /// Reduces what was typed or pasted to the server's root: the scheme
    /// (`http` when none), host, port and any subpath it's served under,
    /// without the web client's own pages (`/login`, `/library/<id>`, …).
    public static func normalizedAddress(_ raw: String) -> String? {
        var address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        if !address.contains("://") {
            address = "http://\(address)"
        }
        guard var components = URLComponents(string: address),
              let host = components.host, !host.isEmpty else { return nil }
        components.fragment = nil
        components.query = nil
        components.user = nil
        components.password = nil
        var parts = components.path.split(separator: "/").map(String.init)
        if let page = parts.firstIndex(where: { webClientPages.contains($0.lowercased()) }) {
            parts = Array(parts[..<page])
        }
        components.path = parts.isEmpty ? "" : "/" + parts.joined(separator: "/")
        guard var result = components.url?.absoluteString else { return nil }
        while result.hasSuffix("/") { result.removeLast() }
        return result
    }

    /// The web client's top-level pages, and the API's own root: whatever
    /// comes before one of these is where the server lives.
    static let webClientPages: Set<String> = [
        "login", "library", "item", "config", "author", "series", "collection", "playlist",
        "account", "share", "api", "audiobook", "podcast"
    ]

    /// A listening session's track: no sign-in needed while it's open.
    public static func sessionTrackURL(base: URL, sessionID: String, index: Int, fileExtension: String?) -> URL? {
        url(base: base, path: "/public/session/\(sessionID)/track/\(index)", query: [], fileExtension: fileExtension)
    }

    /// The file itself, signed in with `token`.
    public static func fileURL(base: URL, itemID: String, fileID: String, token: String, fileExtension: String?) -> URL? {
        url(base: base, path: "/api/items/\(itemID)/file/\(fileID)", query: [URLQueryItem(name: "token", value: token)], fileExtension: fileExtension)
    }

    /// An item's cover, as a JPEG (which Sonos shows; the server would
    /// otherwise answer WebP to a client that takes it). Covers need no
    /// sign-in.
    public static func coverURL(base: URL, itemID: String, width: Int? = nil) -> URL? {
        var query = [URLQueryItem(name: "format", value: "jpeg")]
        if let width {
            query.append(URLQueryItem(name: "width", value: "\(width)"))
        }
        return url(base: base, path: "/api/items/\(itemID)/cover", query: query, fileExtension: nil)
    }

    /// An author's picture, as a book's cover is asked for.
    public static func authorImageURL(base: URL, authorID: String, width: Int? = nil) -> URL? {
        var query = [URLQueryItem(name: "format", value: "jpeg")]
        if let width {
            query.append(URLQueryItem(name: "width", value: "\(width)"))
        }
        return url(base: base, path: "/api/authors/\(authorID)/image", query: query, fileExtension: nil)
    }

    /// The file a stream URL Cue built plays, read back off the URL — for a
    /// speaker's queue, which hands back only the URL. A session's track
    /// names its item through the session (`itemForSession`) and its index
    /// but not its file id, which reads as `-`; a file URL names its item
    /// and file but not its index, which reads as 0.
    /// `AudiobookshelfPartID.isSameFile(as:)` matches either against the
    /// book's own.
    public static func partID(fromStreamURL raw: String, itemForSession: (String) -> String?) -> AudiobookshelfPartID? {
        let decoded = raw.removingPercentEncoding ?? raw
        let path = decoded.components(separatedBy: "?")[0]
        let parts = path.split(separator: "/").map(String.init)
        if let session = parts.lastIndex(of: "session"), parts.count > session + 3, parts[session + 2] == "track",
           let index = Int(parts[session + 3]), let itemID = itemForSession(parts[session + 1]) {
            return AudiobookshelfPartID(itemID: itemID, index: index, fileID: "-")
        }
        if let items = parts.lastIndex(of: "items"), parts.count > items + 3, parts[items + 2] == "file" {
            return AudiobookshelfPartID(itemID: parts[items + 1], index: 0, fileID: parts[items + 3])
        }
        return nil
    }

    /// Whether a URL is one of the two kinds Cue builds for a book's file.
    public static func isStreamURL(_ raw: String) -> Bool {
        let decoded = raw.removingPercentEncoding ?? raw
        return (decoded.contains("/public/session/") && decoded.contains("/track/"))
            || (decoded.contains("/api/items/") && decoded.contains("/file/"))
    }

    /// The extension a speaker is shown for a file: `.m4b` is an `.m4a`
    /// by another name, and the name Sonos knows.
    public static func extensionHint(for fileExtension: String?) -> String? {
        guard let ext = fileExtension?.lowercased(), !ext.isEmpty else { return nil }
        return ext == "m4b" ? "m4a" : ext
    }

    private static func url(base: URL, path: String, query: [URLQueryItem], fileExtension: String?) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.path = components.path.appending(path)
        var items = query
        if let hint = extensionHint(for: fileExtension) {
            items.append(URLQueryItem(name: "ext", value: ".\(hint)"))
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }
}

/// What a book's file is called in Cue: its item, its place among the
/// book's files (the session track index) and its file id, in one string —
/// a `PlayableContent` id, which has to rebuild the file's URL with
/// nothing else to go on.
public struct AudiobookshelfPartID: Hashable, Sendable {
    public let itemID: String
    public let index: Int
    public let fileID: String

    public init(itemID: String, index: Int, fileID: String) {
        self.itemID = itemID
        self.index = index
        self.fileID = fileID
    }

    public init?(_ string: String) {
        let parts = string.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, !parts[0].isEmpty, let index = Int(parts[1]), !parts[2].isEmpty else { return nil }
        self.init(itemID: parts[0], index: index, fileID: parts[2])
    }

    public var string: String { "\(itemID)|\(index)|\(fileID)" }

    /// The same file of the same item, by whichever of index and file id
    /// both sides know (see `AudiobookshelfURLs.partID(fromStreamURL:)`).
    public func isSameFile(as other: AudiobookshelfPartID) -> Bool {
        guard itemID == other.itemID else { return false }
        if index > 0, other.index > 0 { return index == other.index }
        return fileID != "-" && fileID == other.fileID
    }
}

public extension AudiobookshelfItem {
    /// The book's files, laid end to end.
    var timeline: AudiobookTimeline {
        AudiobookTimeline(partDurations: (media?.tracks ?? []).map(\.duration))
    }

    /// Its chapters: the server's, which are in book time already, else one
    /// a file for a book of several files without marks.
    var chapters: [AudiobookChapter] {
        let marks = media?.chapters ?? []
        if !marks.isEmpty {
            return marks.enumerated().map { index, mark in
                AudiobookChapter(id: index, title: mark.title ?? "Chapter \(index + 1)", start: mark.start, end: mark.end)
            }
        }
        let tracks = media?.tracks ?? []
        guard tracks.count > 1 else { return [] }
        return .perPart(titles: tracks.enumerated().map { $1.title ?? "Part \($0 + 1)" }, timeline: timeline)
    }

    /// Where the listener is, from the server.
    var progress: AudiobookProgress? {
        userMediaProgress?.audiobookProgress(duration: media?.duration)
    }
}

public extension AudiobookshelfMediaProgress {
    func audiobookProgress(duration fallback: Double?) -> AudiobookProgress? {
        guard let currentTime else { return nil }
        return AudiobookProgress(
            position: currentTime,
            duration: duration ?? fallback ?? 0,
            isFinished: isFinished ?? false,
            updatedAt: lastUpdate.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } ?? .distantPast
        )
    }
}
