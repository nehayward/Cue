import Foundation

/// How the library and the status cross WatchConnectivity.
///
/// The iPhone sends the library as a file (`transferFile`): it has no size
/// cap, waits in the system's queue while the watch is away, and is
/// delivered even if the watch app isn't running. The metadata says what
/// the file is and which revision it holds, so the watch can skip a stale
/// one without reading it. The watch answers with its status as
/// application context, where only the latest value matters.
public enum WatchSyncMessage {
    public static let kindKey = "kind"
    public static let revisionKey = "revision"
    public static let libraryKind = "library"
    /// Application-context key the watch's status travels under, as JSON.
    public static let statusKey = "status"

    public static func libraryMetadata(revision: Int) -> [String: Any] {
        [kindKey: libraryKind, revisionKey: revision]
    }

    public static func isLibrary(_ metadata: [String: Any]?) -> Bool {
        metadata?[kindKey] as? String == libraryKind
    }

    public static func revision(in metadata: [String: Any]?) -> Int? {
        if let revision = metadata?[revisionKey] as? Int { return revision }
        // Property-list numbers can come back as NSNumber of another width.
        return (metadata?[revisionKey] as? NSNumber)?.intValue
    }

    public static func statusContext(_ status: WatchStatus) throws -> [String: Any] {
        [statusKey: try JSONEncoder().encode(status)]
    }

    public static func status(in context: [String: Any]) -> WatchStatus? {
        guard let data = context[statusKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchStatus.self, from: data)
    }
}
