
import Foundation

// Define the top-level object
public struct FavoritesList: Codable {
    public var objectType: String
    public var version: String
    public var items: [Favorite]

    enum CodingKeys: String, CodingKey {
        case objectType = "_objectType"
        case version, items
    }
}

// Define the 'Favorite' structure
public struct Favorite: Codable, Identifiable {
    public var objectType: String
    public var id: String
    public var name: String
    public var description: String
    public var imageUrl: String
    public var images: [Image]
    public var service: Service?
    public var resource: ContentResource

    enum CodingKeys: String, CodingKey {
        case objectType = "_objectType"
        case id, name, description, imageUrl, images, service, resource
    }
}

// Define the 'Image' structure
public struct Image: Codable {
    public var objectType: String
    public var url: String

    enum CodingKeys: String, CodingKey {
        case objectType = "_objectType"
        case url
    }
}

// Define the 'Service' structure
public struct Service: Codable {
    public var objectType: String
    public var name: String
    public var id: String
    public var images: [Image]

    enum CodingKeys: String, CodingKey {
        case objectType = "_objectType"
        case name, id, images
    }
}

// Define the 'ContentResource' structure
public struct ContentResource: Codable {
    public var objectType: String
    public var type: String?
    public var id: UniversalMusicObjectId?
    public var name: String?

    enum CodingKeys: String, CodingKey {
        case objectType = "_objectType"
        case type, id, name
    }
}

// Define the 'UniversalMusicObjectId' structure
public struct UniversalMusicObjectId: Codable {
    public var objectType: String
    public var serviceId: String
    public var objectId: String
    public var accountId: String

    enum CodingKeys: String, CodingKey {
        case objectType = "_objectType"
        case serviceId, objectId, accountId
    }
}
