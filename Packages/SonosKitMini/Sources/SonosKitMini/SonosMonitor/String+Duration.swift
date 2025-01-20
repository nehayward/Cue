

// Add these helper functions after the SonosListenerConfig struct and before the SonosListener class
extension String {
    func toDuration() -> Duration {
        let components = self.split(separator: ":").map { String($0) }
        
        switch components.count {
        case 3: // Format: h:mm:ss
            if let h = Int(components[0]),
               let m = Int(components[1]),
               let s = Int(components[2]) {
                return .seconds(h * 3600 + m * 60 + s)
            }
        case 2: // Format: mm:ss
            if let m = Int(components[0]),
               let s = Int(components[1]) {
                return .seconds(m * 60 + s)
            }
        case 1: // Format: ss
            if let s = Int(components[0]) {
                return .seconds(s)
            }
        default:
            return .seconds(0)
        }
        return .seconds(0)
    }
}


