import Foundation

struct DiscoveryInfo: Codable {
    let objectType: String
    let device: DeviceInfo
    let householdId: String
    let locationId: String
    let playerId: String
    let groupId: String
    let websocketUrl: String
    let restUrl: String
    
    enum CodingKeys: String, CodingKey {
        case objectType = "_objectType"
        case device
        case householdId
        case locationId
        case playerId
        case groupId
        case websocketUrl
        case restUrl
    }
}

public struct DeviceInfo: Codable {
    public let objectType: String
    public let id: String
    public let serialNumber: String
    public let model: String
    public let modelDisplayName: String
    public let color: String
    public let capabilities: [String]
    public let deviceFeatures: [Feature]
    public let apiVersion: String
    public let minApiVersion: String
    public let name: String
    public let websocketUrl: String
    public let softwareVersion: String
    public let hwVersion: String
    public let swGen: Int
    public let quarantineReasons: [String]
    
    enum CodingKeys: String, CodingKey {
        case objectType = "_objectType"
        case id
        case serialNumber
        case model
        case modelDisplayName
        case color
        case capabilities
        case deviceFeatures
        case apiVersion
        case minApiVersion
        case name
        case websocketUrl
        case softwareVersion
        case hwVersion
        case swGen
        case quarantineReasons
    }
}

public struct Feature: Codable {
    public let objectType: String
    public let name: String
    
    enum CodingKeys: String, CodingKey {
        case objectType = "_objectType"
        case name
    }
}
