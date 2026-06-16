import Foundation

public struct DeezerContainer<T: Decodable>: Decodable {
    public let data: [T]
}
