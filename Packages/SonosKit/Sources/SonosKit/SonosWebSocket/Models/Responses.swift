import Foundation

/// Response for group information
public struct GroupResponse: Codable {
    let groups: [Group]
    
    struct Group: Codable {
        let id: String
        let name: String
        let players: [Player]
        
        struct Player: Codable {
            let id: String
            let name: String
            let capabilities: [String]
        }
    }
}

/// Response for metadata status
struct MetadataResponse: Codable {
    let _objectType: String
    let container: Container?
    let currentItem: CurrentItem?
    
    struct Container: Codable {
        let _objectType: String
        let name: String
        let type: String
        let id: MusicObjectId
        let images: [Image]
    }
    
    struct CurrentItem: Codable {
        let _objectType: String
        let track: Track?
        let policies: Policies?
    }
    
    struct Track: Codable {
        let _objectType: String
        let type: String
        let name: String
        let imageUrl: String?
        let images: [Image]
        let album: Album
        let artist: Artist
        let id: MusicObjectId
        let service: Service
        let durationMillis: Int
        let quality: AudioQuality
    }
    
    struct Album: Codable {
        let _objectType: String
        let name: String
    }
    
    struct Artist: Codable {
        let _objectType: String
        let name: String
    }
    
    struct Service: Codable {
        let _objectType: String
        let name: String
        let id: String
        let images: [Image]
    }
    
    struct Image: Codable {
        let _objectType: String
        let url: String
    }
    
    struct Policies: Codable {
        let _objectType: String
    }
    
    struct MusicObjectId: Codable {
        let _objectType: String
        let objectId: String
        let serviceId: String?
        let accountId: String?
    }
}

/// Response for household information
struct HouseholdResponse: Codable {
    let householdId: String
}

/// Response for audio clip operations
public struct AudioClipResponse: Codable {
    let success: Bool
    let clipId: String?
    let error: String?
}

/// Response for subscription operations
struct SubscriptionResponse: Codable {
    let namespace: String
    let householdId: String
    let locationId: String
    let groupId: String
    let response: String
    let success: Bool
    let type: String
}

/// Response for metadata status updates
public struct MetadataStatusUpdate: Codable {
    let namespace: String
    let householdId: String
    let locationId: String
    let groupId: String
    let name: String
    let type: String
    let _objectType: String
    let container: Container?
    let currentItem: CurrentItem?
    let nextItem: CurrentItem?
    
    struct Container: Codable {
        let _objectType: String
        let name: String?
        let type: String?
        let id: MusicObjectId?
        let service: Service?
        let images: [Image]
    }
    
    struct CurrentItem: Codable {
        let _objectType: String
        let track: Track?
        let policies: Policies?
    }
    
    struct Track: Codable {
        let _objectType: String
        let type: String
        let name: String
        let imageUrl: String?
        let images: [Image]
        let album: Album
        let artist: Artist
        let id: MusicObjectId
        let service: Service?
        let durationMillis: Int
        let quality: AudioQuality?
    }
    
    struct Album: Codable {
        let _objectType: String
        let name: String
    }
    
    struct Artist: Codable {
        let _objectType: String
        let name: String
    }
    
    struct Service: Codable {
        let _objectType: String
        let name: String
        let id: String
        let images: [Image]
    }
    
    struct Image: Codable {
        let _objectType: String
        let url: String
    }
    
    struct Policies: Codable {
        let _objectType: String
    }
    
    struct MusicObjectId: Codable {
        let _objectType: String
        let objectId: String
        let serviceId: String?
        let accountId: String?
    }
}

/// Wrapper for subscription response
struct SubscriptionResponseWrapper: Codable {
    let response: SubscriptionResponse
} 
