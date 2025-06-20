import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()
    private let service = "com.sonos.mediaservers"
    
    private init() {}
    
    func saveMediaServers(householdId: String, servers: [MediaServer]) {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(servers)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: householdId,
                kSecValueData as String: data
            ]
            
            // First try to delete any existing data
            SecItemDelete(query as CFDictionary)
            
            // Then add the new data
            let status = SecItemAdd(query as CFDictionary, nil)
            if status != errSecSuccess {
                print("❌ Failed to save media servers to keychain: \(status)")
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
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            print("❌ No cached media servers found for household: \(householdId)")
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
            kSecAttrAccount as String: householdId
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            print("✅ Successfully cleared cached media servers for household: \(householdId)")
        } else {
            print("❌ Failed to clear cached media servers: \(status)")
        }
    }
} 
