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
        
        // Debug print all found interfaces
        for interface in interfaces {
            print("Found interface: \(interface.name) - \(interface.address) (\(interface.isWired ? "Wired" : "WiFi"))")
        }
        
        // Prefer wired connection
        if let wiredInterface = interfaces.first(where: { $0.isWired }) {
            print("Using wired connection: \(wiredInterface.address)")
            return wiredInterface.address
        }
        
        // Fall back to WiFi
        if let wifiInterface = interfaces.first(where: { !$0.isWired }) {
            print("Using WiFi connection: \(wifiInterface.address)")
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
                print("Found interface name: \(name)")
                if let address = getAddressFromInterface(interface) {
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
