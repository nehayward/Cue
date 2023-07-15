import Foundation
import Observation

@Observable
public class SonosScene {
    public var name: String = ""
    public var rooms: [Room] = []

    public init(name: String, rooms: [Room]) {
        self.name = name
        self.rooms = rooms
    }
}
