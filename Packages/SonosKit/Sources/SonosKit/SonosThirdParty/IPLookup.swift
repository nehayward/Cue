import Foundation

final class IPActive {
    struct NetworkInterface {
        let name: String
        let address: String
        let isWired: Bool
        
        var description: String {
            "\(isWired ? "Wired" : "WiFi") connection on \(name): \(address)"
        }
    }
    
    func getIPAddress() -> String? {
        let interfaces = getAllInterfaces()
        
        // Prefer wired connection
        if let wiredInterface = interfaces.first(where: { $0.isWired }) {
            return wiredInterface.address
        }
        
        // Fall back to WiFi
        if let wifiInterface = interfaces.first(where: { !$0.isWired }) {
            return wifiInterface.address
        }
        
        return nil
    }
    
    private func getAllInterfaces() -> [NetworkInterface] {
        var interfaces: [NetworkInterface] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil

        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let interface = ptr?.pointee {
            defer { ptr = interface.ifa_next }

            let name = String(cString: interface.ifa_name)

            // Only process IPv4 and en interfaces
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) && name.hasPrefix("en") {
                if let address = getAddressFromInterface(interface) {
                    // Skip link-local (169.254.x.x) addresses. They're auto-
                    // configured fallbacks that Sonos cannot route to, so
                    // binding our NOTIFY listener there means the speaker's
                    // events disappear into the void — no media servers
                    // ever get cached. Common on iOS Simulator where the
                    // Mac exposes several virtual NICs (en7, en11, …).
                    guard !address.hasPrefix("169.254.") else {
                        #if DEBUG
                        print("Skipping link-local interface \(name): \(address)")
                        #endif
                        continue
                    }
                    #if DEBUG
                    print("Found interface \(name): \(address)")
                    #endif
                    // en0 is WiFi, all other en interfaces are considered wired
                    let isWired = name != "en0"
                    interfaces.append(NetworkInterface(name: name, address: address, isWired: isWired))
                }
            }
        }
        return interfaces
    }
    
    private func getAddressFromInterface(_ interface: ifaddrs) -> String? {
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(interface.ifa_addr,
                         socklen_t(interface.ifa_addr.pointee.sa_len),
                         &hostname,
                         socklen_t(hostname.count),
                         nil,
                         0,
                         NI_NUMERICHOST) == 0 else {
            return nil
        }
        return String(cString: hostname)
    }
}
