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
        let fromMetadata = item.metadata?.audioCodec?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
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
