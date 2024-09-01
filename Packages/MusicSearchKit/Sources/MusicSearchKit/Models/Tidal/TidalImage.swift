import Foundation

public struct TidalImage: Codable {
    public let url: String
    public let width: Int
    public let height: Int
}

extension Array where Element == TidalImage {
    public var biggestImageURL: URL? {
        let largest = self.sorted(by: { $0.height > $1.height})
        return URL(string: largest.first?.url ?? "")
    }

    public var thumbnail: URL? {
        let smallest = self.sorted(by: { $0.height < $1.height})
        return URL(string: smallest.first(where: { $0.width > 300 })?.url ?? "")
    }
}
