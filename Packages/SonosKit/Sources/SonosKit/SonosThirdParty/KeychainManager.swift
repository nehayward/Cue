import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()
    private let service = "com.sonos.mediaservers"
    private let accessGroup = "group.com.clic"
    
    private init() {}
    
    func saveMediaServers(householdId: String, servers: [MediaServer]) {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(servers)
            
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: householdId,
                kSecAttrAccessGroup as String: accessGroup
            ]
            
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
            
            // Try to update existing item first
            var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            
            if status == errSecItemNotFound {
                // Item doesn't exist, so add it
                var addQuery = query
                addQuery[kSecValueData as String] = data
                status = SecItemAdd(addQuery as CFDictionary, nil)
            }
            
            if status != errSecSuccess {
                let errorMessage = getKeychainErrorMessage(status)
                print("❌ Failed to save media servers to keychain: \(status) - \(errorMessage)")
            } else {
                print("✅ Successfully cached media servers for household: \(householdId)")
            }
        } catch {
            print("❌ Failed to encode media servers: \(error)")
        }
    }
    
    func getMediaServers(householdId: String) -> [MediaServer]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: householdId,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            if status != errSecItemNotFound {
                let errorMessage = getKeychainErrorMessage(status)
                print("❌ Keychain error retrieving media servers: \(status) - \(errorMessage)")
            } else {
                print("❌ No cached media servers found for household: \(householdId)")
            }
            return nil
        }
        
        do {
            let servers = try JSONDecoder().decode([MediaServer].self, from: data)
            print("✅ Retrieved \(servers.count) cached media servers for household: \(householdId)")
            return servers
        } catch {
            print("❌ Failed to decode cached media servers: \(error)")
            return nil
        }
    }
    
    func clearMediaServers(householdId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: householdId,
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            print("✅ Successfully cleared cached media servers for household: \(householdId)")
        } else if status != errSecItemNotFound {
            let errorMessage = getKeychainErrorMessage(status)
            print("❌ Failed to clear cached media servers: \(status) - \(errorMessage)")
        }
    }
    
    private func getKeychainErrorMessage(_ status: OSStatus) -> String {
        switch status {
        case errSecSuccess: return "Success"
        case errSecUnimplemented: return "Function or operation not implemented"
        case errSecParam: return "Invalid parameter"
        case errSecAllocate: return "Failed to allocate memory"
        case errSecNotAvailable: return "No keychain is available"
        case errSecDuplicateItem: return "The item already exists"
        case errSecItemNotFound: return "The item cannot be found"
        case errSecInteractionNotAllowed: return "User interaction not allowed"
        case errSecDecode: return "Unable to decode the provided data"
        case errSecAuthFailed: return "Authentication failed"
        default: return "Unknown error"
        }
    }
}
