import Foundation
import Observation

public struct SonosScene {
    public var name: String = ""
    public var rooms: [Room] = []

    public init(name: String, rooms: [Room]) {
        self.name = name
        self.rooms = rooms
    }
}
