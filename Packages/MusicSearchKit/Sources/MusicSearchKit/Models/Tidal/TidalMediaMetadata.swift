
public struct TidalMediaMetadata: Codable {
    public var tags: [String]?
    
    public var hasDolbyAtmos: Bool {
        tags?.contains { $0.caseInsensitiveCompare("dolby_atmos") == .orderedSame } ?? false
    }
    
    public var hasLossLess: Bool {
        tags?.contains { $0.caseInsensitiveCompare("dolby_atmos") == .orderedSame } ?? false
    }
}
