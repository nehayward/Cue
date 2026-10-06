import Foundation

/// What crosses WatchConnectivity: each side's application context — only
/// the latest matters, the system keeps it for an app that isn't running,
/// and it works between simulators. The iPhone's carries the picks and its
/// sign-ins (`WatchCredentials`); the watch's carries the picks as it has
/// them. Each side merges what arrives (`WatchPicks.merged`). The picks
/// travel packed, with a `sentAt` stamp so sending them again always counts
/// as a change.
public enum WatchSyncMessage {
    public static let picksKey = "picks"
    public static let credentialsKey = "credentials"
    public static let sentAtKey = "sentAt"

    public static func context(picks: WatchPicks, credentials: WatchCredentials? = nil, sentAt: Date = .now) throws -> [String: Any] {
        var context: [String: Any] = [
            picksKey: pack(try picks.encoded()),
            sentAtKey: sentAt.timeIntervalSince1970,
        ]
        if let credentials {
            context[credentialsKey] = try JSONEncoder().encode(credentials)
        }
        return context
    }

    public static func picks(in context: [String: Any]) -> WatchPicks? {
        guard let packed = context[picksKey] as? Data, let data = unpack(packed) else { return nil }
        return try? WatchPicks.decoded(from: data)
    }

    public static func credentials(in context: [String: Any]) -> WatchCredentials? {
        guard let data = context[credentialsKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchCredentials.self, from: data)
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
