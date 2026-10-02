import Foundation

/// The keys a song and a pick have, the same on both devices and the same
/// as the iPhone's download manager gives them (`DownloadNaming.key`,
/// `containerKey`): a song is one file however many picks hold it, and a
/// pick made on one device shows as made on the other.
public enum WatchKeys {
    /// The song's id with path separators and the extension dot made safe;
    /// Plex ids bare, others behind their service's name.
    public static func song(source: WatchSource, id: String) -> String {
        let safe = id
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return source == .plex ? safe : "\(source.rawValue)-\(safe)"
    }

    /// The pick's kind in front of the same safe id, so an album and a
    /// playlist that share an id on the server stay apart.
    public static func pick(kind: WatchPick.Kind, source: WatchSource, id: String) -> String {
        "\(kind.rawValue)-\(song(source: source, id: id))"
    }
}
