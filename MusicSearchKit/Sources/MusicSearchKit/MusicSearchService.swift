import Foundation

public final class MusicSearchService {
    private let appleMusicSearchAPI = AppleMusicSearchAPI()

    public init() {

    }
    
    public func search(song: String, artist: String) async -> [ItunesResult] {
        await appleMusicSearchAPI.search(for: "\(song) \(artist)")
    }
}



