
public struct PlexLibrarySectionContainer: Codable {
    let size: Int
    let allowSync: Bool
    let title1: String
    let Directory: [PlexLibrarySection]
}

public struct PlexLibrarySection: Codable, Identifiable {
    public var id: String { uuid }
    
    public let allowSync: Bool
    public let key: String
    public let type: String
    public let title: String
    public let uuid: String
}
