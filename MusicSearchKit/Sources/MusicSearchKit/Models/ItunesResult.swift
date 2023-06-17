import Foundation

public struct ItunesResult: Identifiable, Decodable {
    public var id: String { trackID.description }
    public let artistName: String
    public let trackName: String
    public let album: String
    public let artistID: Int
    public let collectionID: Int?
    public let trackID: Int
    public let type: String
    public let artworkUrl100: String
    public var artworkURL: String {
        artworkUrl100.replacingOccurrences(of: "100", with: "500")
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type != "track" {
            self.artistName = ""
            self.trackName = ""
            self.album = ""
            self.artworkUrl100 = ""
            self.artistID = 0
            self.collectionID = 0
            self.trackID = 0
            self.type = ""
            return
        }
        self.artistName = try container.decode(String.self, forKey: .artistName)
        self.trackName = try container.decode(String.self, forKey: .trackName)
        self.album = try container.decodeIfPresent(String.self, forKey: .album) ?? ""
        self.artworkUrl100 = try container.decode(String.self, forKey: .artworkUrl100)
        self.artistID = try container.decode(Int.self, forKey: .artistId)
        self.collectionID = try container.decodeIfPresent(Int.self, forKey: .collectionId)
        self.trackID = try container.decode(Int.self, forKey: .trackId)
        self.type = type
    }

    enum CodingKeys: String, CodingKey {
        case type = "wrapperType"
        case artistName
        case trackName
        case album = "collectionName"
        case artworkUrl100
        case artistId
        case collectionId
        case trackId
    }

}
