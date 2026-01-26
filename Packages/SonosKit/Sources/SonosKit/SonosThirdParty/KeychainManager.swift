import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private let service = "com.sonos.mediaservers"
    private let accessGroup = "group.com.clic"

    private init() {}

    // MARK: - Public API

    func saveMediaServers(householdId: String, servers: [MediaServer]) {
        #if DEBUG
        if handleDebugSave(householdId: householdId, servers: servers) {
            return
        }
        #endif

        guard let data = try? Self.encoder.encode(servers) else {
            print("Failed to encode media servers")
            return
        }

        let query = baseQuery(for: householdId)
        let attributes: [String: Any] = [kSecValueData as String: data]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        if status != errSecSuccess {
            print("Failed to save media servers: \(Self.errorMessage(for: status))")
        }
    }

    func getMediaServers(householdId: String) -> [MediaServer]? {
        #if DEBUG
        if let debugResult = handleDebugLoad(householdId: householdId) {
            return debugResult
        }
        #endif

        var query = baseQuery(for: householdId)
        query[kSecReturnData as String] = true

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                print("Keychain error: \(Self.errorMessage(for: status))")
            }
            return nil
        }

        return try? Self.decoder.decode([MediaServer].self, from: data)
    }

    func clearMediaServers(householdId: String) {
        #if DEBUG
        if shouldSkipKeychainInDebug { return }
        #endif

        let status = SecItemDelete(baseQuery(for: householdId) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("Failed to clear media servers: \(Self.errorMessage(for: status))")
        }
    }

    // MARK: - Private Helpers

    private func baseQuery(for householdId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: householdId,
            kSecAttrAccessGroup as String: accessGroup
        ]
    }

    private static func errorMessage(for status: OSStatus) -> String {
        switch status {
        case errSecSuccess: return "Success"
        case errSecUnimplemented: return "Not implemented"
        case errSecParam: return "Invalid parameter"
        case errSecAllocate: return "Memory allocation failed"
        case errSecNotAvailable: return "Keychain not available"
        case errSecDuplicateItem: return "Item already exists"
        case errSecItemNotFound: return "Item not found"
        case errSecInteractionNotAllowed: return "Interaction not allowed"
        case errSecDecode: return "Decode failed"
        case errSecAuthFailed: return "Authentication failed"
        default: return "Unknown error (\(status))"
        }
    }
}

// MARK: - Debug/Preview Support
#if DEBUG
extension KeychainManager {
    private static let debugCacheURL = URL(fileURLWithPath: "/tmp/com.clic.debug.mediaservers.json")

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var shouldSkipKeychainInDebug: Bool { isPreview }

    /// Returns `true` if keychain should be skipped (preview mode)
    func handleDebugSave(householdId: String, servers: [MediaServer]) -> Bool {
        saveToDebugCache(householdId: householdId, servers: servers)
        return isPreview
    }

    /// Returns servers from debug cache if in preview mode, nil to fall through to keychain
    func handleDebugLoad(householdId: String) -> [MediaServer]? {
        guard isPreview else { return nil }
        return loadFromDebugCache(householdId: householdId) ?? []
    }

    private func saveToDebugCache(householdId: String, servers: [MediaServer]) {
        var allData = loadAllDebugCache() ?? [:]
        allData[householdId] = servers
        guard let data = try? Self.encoder.encode(allData) else { return }
        try? data.write(to: Self.debugCacheURL)
    }

    private func loadFromDebugCache(householdId: String) -> [MediaServer]? {
        loadAllDebugCache()?[householdId]
    }

    private func loadAllDebugCache() -> [String: [MediaServer]]? {
        guard let data = try? Data(contentsOf: Self.debugCacheURL) else { return nil }
        return try? Self.decoder.decode([String: [MediaServer]].self, from: data)
    }
}
#endif
