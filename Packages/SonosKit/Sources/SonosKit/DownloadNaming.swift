import Foundation

/// How a download is named on disk and on its background `URLSession`
/// task. Pure, so the app's download manager and its tests share one
/// answer for what a track's file is called and how a task is matched back
/// to it after a relaunch with no manifest in memory.
public enum DownloadNaming {
    /// Filesystem-safe key for a track: its service and id with path
    /// separators and the extension dot neutralized. Plex keeps the bare id
    /// the first build used, so its downloads carry over.
    public static func key(for item: PlayableContent) -> String {
        let id = item.content.id
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return item.content.service == .plex ? id : "\(item.content.service.sonosRawValue)-\(id)"
    }

    /// The extension the file is saved with: the codec the catalog reports
    /// when it looks like one, else the URL's, else `mp3`.
    public static func fileExtension(for item: PlayableContent, url: URL) -> String {
        // The suffix the stream really arrives with — the transcode target
        // when Streaming Quality is on, the file's own otherwise — so the
        // player reads the saved copy as what it is.
        let fromMetadata = item.playbackFileExtension ?? ""
        if !fromMetadata.isEmpty, fromMetadata.count <= 5 { return fromMetadata }
        let fromURL = url.pathExtension.lowercased()
        return fromURL.isEmpty ? "mp3" : fromURL
    }

    /// Key and extension travel with the session task, so the relay can put
    /// a finished file in place before the system deletes the temporary
    /// copy — even after a relaunch with no manifest loaded.
    public static func taskDescription(key: String, fileExtension: String) -> String {
        "\(key)|\(fileExtension)"
    }

    public static func parseTaskDescription(_ description: String?) -> (key: String, fileExtension: String)? {
        guard let description else { return nil }
        let parts = description.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    /// Fraction done, clamped to 0…1; zero until the size is known.
    public static func progress(received: Int64, expected: Int64) -> Double {
        guard expected > 0 else { return 0 }
        return min(1, max(0, Double(received) / Double(expected)))
    }
}

/// Checks on what a download brings, pure so the download manager and its
/// tests share them.
public enum DownloadChecks {
    /// The least a converted song can weigh: half what `seconds` at the
    /// bitrate its URL asks for (`musicBitrate` on Plex, `maxBitRate` on
    /// Subsonic) comes to — Opus runs under its target on quiet passages.
    /// A conversion arrives with no length, so one the server broke off
    /// ends like a whole one; anything lighter was cut short. Nil when the
    /// URL asks for no bitrate (the original file, which comes with its
    /// length) or the song's length isn't known.
    public static func minimumConvertedSize(seconds: Double?, url: URL) -> Int64? {
        guard let seconds, seconds > 5,
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let kbps = query.first(where: { ["musicBitrate", "maxBitRate"].contains($0.name) })?.value.flatMap(Int.init),
              kbps > 0 else { return nil }
        return Int64(seconds * Double(kbps) * 125 / 2)
    }

    /// The same Plex conversion asked for as `client`, in a transcode
    /// session of its own (`cue-download-<ratingKey>`), or any other URL as
    /// it is. Plex ends a transcode when the same client starts another,
    /// so conversions that run together each need a client of their own;
    /// and a request in a session that's already transcoding replaces that
    /// transcode, so a download in the player's (`cue-<ratingKey>`) could
    /// end the song playing.
    public static func plexConversion(_ url: URL, client: String) -> URL {
        guard url.path.contains("/transcode/universal/"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let ratingKey = components.queryItems?.first { $0.name == "path" }?.value
            .flatMap { path in path.split(separator: "/").last.map { String($0) } }
        components.queryItems = components.queryItems?.map { item in
            switch item.name {
            case "X-Plex-Client-Identifier":
                return URLQueryItem(name: item.name, value: client)
            case "session":
                return ratingKey.map { URLQueryItem(name: item.name, value: "cue-download-\($0)") } ?? item
            default:
                return item
            }
        }
        return components.url ?? url
    }

    /// The Plex client a URL asks as, if any.
    public static func plexClient(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "X-Plex-Client-Identifier" }?.value
    }
}

/// Every item of a list a server hands over a page at a time, or nil if a
/// page fails — for a download, which would otherwise remember a list cut
/// short as the whole thing.
public enum PagedList {
    /// `page(offset)` answers a page and, where the server says, the
    /// list's total, or nil when it fails. The total says when to stop, so
    /// no page past the end is asked for (Plex answers one with nothing
    /// that decodes, which would read as a failure); with no total, a
    /// short page is the end, and an empty one always is.
    public static func all<Item>(
        pageSize: Int,
        maxPages: Int = 200,
        page: (Int) async -> (items: [Item], total: Int?)?
    ) async -> [Item]? {
        var items: [Item] = []
        var total: Int?
        for _ in 0 ..< maxPages {
            guard let answer = await page(items.count) else { return nil }
            total = total ?? answer.total
            items += answer.items
            let done = answer.items.isEmpty
                || items.count >= total ?? .max
                || (total == nil && answer.items.count < pageSize)
            if done { break }
        }
        return items
    }
}
