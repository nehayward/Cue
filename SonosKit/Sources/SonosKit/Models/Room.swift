import Foundation

public struct Room {
    public let UUID: String
    public let location: String
    public let zoneName: String

    public var ip: String {
        let components = URLComponents(string: location)
        return components?.host ?? ""
    }
}

