//
//  DiscoveryInfo.swift
//  SonosKitMini
//
//  Created by Nick Hayward on 12/20/24.
//
import Foundation

public struct DeviceInfo: Codable, Hashable, Equatable {
    public let objectType: String?
    public let id: String
    public let serialNumber: String
    public let model: String
    public let modelDisplayName: String
    public let color: String?
    public let capabilities: [String]?
    public let deviceFeatures: [Feature]?
    public let apiVersion: String
    public let minApiVersion: String
    public let name: String
    public let websocketUrl: String?
    public let softwareVersion: String
    public let hwVersion: String
    public let swGen: Int
    public let quarantineReasons: [String]?
    
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

public struct Feature: Codable, Hashable, Equatable {
    public let objectType: String
    public let name: String
    
    enum CodingKeys: String, CodingKey {
        case objectType = "_objectType"
        case name
    }
}
