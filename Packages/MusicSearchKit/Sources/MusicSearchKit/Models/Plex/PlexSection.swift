
public struct PlexLibrarySectionContainer: Codable {
    let size: Int
    let allowSync: Bool?
    let title1: String?
    let Directory: [PlexLibrarySection]
}

public struct PlexLibrarySection: Codable, Identifiable {
    public var id: String { uuid }
    
    public let allowSync: Bool?
    public let key: String
    public let type: String
    public let title: String
    public let uuid: String
    /// The metadata agent the library is matched with (e.g. Audnexus's, for
    /// books); one hint that a Music library is kept for audiobooks.
    public let agent: String?
    /// The server is scanning the library's folders.
    public let refreshing: Bool?
}
