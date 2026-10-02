import Foundation

/// The keys a song and a collection have on both devices. They match the
/// iPhone's download manager (`DownloadNaming.key`, `containerKey`), so a
/// song is one file however it got on the watch, and an album added on one
/// device shows as added on the other.
public enum WatchKeys {
    /// The song's id with path separators and the extension dot made safe;
    /// Plex ids bare, others behind their service's name.
    public static func track(source: WatchSource, id: String) -> String {
        let safe = id
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return source == .plex ? safe : "\(source.rawValue)-\(safe)"
    }

    /// The collection's kind in front of the same safe id, so an album and a
    /// playlist that share an id on the server stay apart.
    public static func collection(kind: WatchCollection.Kind, source: WatchSource, id: String) -> String {
        "\(kind.rawValue)-\(track(source: source, id: id))"
    }
}
