import Foundation

/// How the library and the status cross WatchConnectivity.
///
/// The iPhone sends the library as application context: only the latest
/// matters, the system keeps it for a watch app that isn't running, and it
/// works between simulators, where file transfers never arrive. It travels
/// compressed with a `sentAt` stamp, so sending it again always counts as a
/// change and is delivered. A library too big for application context goes
/// as a file instead (`transferFile`), whose metadata says what it is and
/// which revision it holds. The watch answers with its status as its own
/// application context — each side's context is separate.
public enum WatchSyncMessage {
    public static let kindKey = "kind"
    public static let revisionKey = "revision"
    public static let libraryKind = "library"
    /// Application-context key the library travels under, packed.
    public static let libraryKey = "library"
    public static let sentAtKey = "sentAt"
    /// Application-context key the watch's status travels under, as JSON.
    public static let statusKey = "status"
    /// The largest packed library sent as application context. WatchConnectivity
    /// refuses payloads somewhere past 64 KB; this leaves room.
    public static let contextLimit = 48_000

    // MARK: - Library as application context

    /// The library as application context, or nil when it's too big for it
    /// and has to go as a file.
    public static func libraryContext(_ library: WatchLibrary, sentAt: Date = .now) throws -> [String: Any]? {
        let packed = pack(try library.encoded())
        guard packed.count <= contextLimit else { return nil }
        return [
            kindKey: libraryKind,
            revisionKey: library.revision,
            libraryKey: packed,
            sentAtKey: sentAt.timeIntervalSince1970,
        ]
    }

    /// The library in an application context, if there's one.
    public static func library(in context: [String: Any]) -> WatchLibrary? {
        guard let packed = context[libraryKey] as? Data, let data = unpack(packed) else { return nil }
        return try? WatchLibrary.decoded(from: data)
    }

    // MARK: - Library as a file

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

    // MARK: - Status

    public static func statusContext(_ status: WatchStatus) throws -> [String: Any] {
        [statusKey: try JSONEncoder().encode(status)]
    }

    public static func status(in context: [String: Any]) -> WatchStatus? {
        guard let data = context[statusKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchStatus.self, from: data)
    }

    // MARK: - Packing

    private enum Packing: UInt8 {
        case plain = 0
        case lzfse = 1
    }

    /// JSON is mostly repeated stream URLs, so it shrinks several times
    /// over. LZFSE where the system has it; plain elsewhere (the Linux
    /// test runs). A leading byte says which.
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
