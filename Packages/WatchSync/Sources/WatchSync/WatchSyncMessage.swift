import Foundation

/// How the library, the sign-ins and the status cross WatchConnectivity.
///
/// Each side keeps one application context — only the latest matters, the
/// system keeps it for an app that isn't running, and it works between
/// simulators, where file transfers never arrive. The iPhone's carries the
/// library and its sign-ins (`WatchCredentials`); the watch's carries the
/// library and its status. Each side takes the other's library when its
/// revision is newer. The library travels packed, with a `sentAt` stamp so
/// sending it again always counts as a change. One too big for a context
/// goes as a file instead (`transferFile`), whose metadata says what it is
/// and which revision it holds.
public enum WatchSyncMessage {
    public static let kindKey = "kind"
    public static let revisionKey = "revision"
    public static let libraryKind = "library"
    /// Application-context key the library travels under, packed.
    public static let libraryKey = "library"
    public static let sentAtKey = "sentAt"
    /// Application-context key the iPhone's sign-ins travel under, as JSON.
    public static let credentialsKey = "credentials"
    /// Application-context key the watch's status travels under, as JSON.
    public static let statusKey = "status"
    /// The largest packed library sent as application context. WatchConnectivity
    /// refuses payloads somewhere past 64 KB; this leaves room.
    public static let contextLimit = 48_000

    // MARK: - Application context

    /// One side's application context: the library when it fits, and what
    /// else that side sends — the iPhone its sign-ins, the watch its status.
    /// `libraryFits` false means the library has to go as a file.
    public static func context(
        library: WatchLibrary?,
        credentials: WatchCredentials? = nil,
        status: WatchStatus? = nil,
        sentAt: Date = .now
    ) throws -> (context: [String: Any], libraryFits: Bool) {
        var context: [String: Any] = [sentAtKey: sentAt.timeIntervalSince1970]
        var fits = true
        if let library {
            let packed = pack(try library.encoded())
            if packed.count <= contextLimit {
                context[kindKey] = libraryKind
                context[revisionKey] = library.revision
                context[libraryKey] = packed
            } else {
                fits = false
            }
        }
        if let credentials {
            context[credentialsKey] = try JSONEncoder().encode(credentials)
        }
        if let status {
            context[statusKey] = try JSONEncoder().encode(status)
        }
        return (context, fits)
    }

    /// The library in an application context, if there's one.
    public static func library(in context: [String: Any]) -> WatchLibrary? {
        guard let packed = context[libraryKey] as? Data, let data = unpack(packed) else { return nil }
        return try? WatchLibrary.decoded(from: data)
    }

    public static func credentials(in context: [String: Any]) -> WatchCredentials? {
        guard let data = context[credentialsKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchCredentials.self, from: data)
    }

    public static func status(in context: [String: Any]) -> WatchStatus? {
        guard let data = context[statusKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchStatus.self, from: data)
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
