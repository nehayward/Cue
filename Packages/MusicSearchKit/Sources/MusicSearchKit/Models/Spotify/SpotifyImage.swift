import Foundation

public struct SpotifyImage: Equatable, Decodable, Sendable {
    public let height: Int?
    public let url: String
    public let width: Int?
}

extension Array where Element == SpotifyImage {
    public var biggestImageURL: URL? {
        let largest = self.sorted(by: { $0.height ?? 0 > $1.height ?? 0 })
        return URL(string: largest.first?.url ?? "")
    }

    public var thumbnail: URL? {
        let smallest = self.sorted(by: { $0.height ?? 0 < $1.height ?? 0 })
        return URL(string: smallest.first?.url ?? "")
    }
}
