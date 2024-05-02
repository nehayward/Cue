import Foundation
import SonosKit
import UIKit

extension Track {
    @MainActor
    public var nowPlayingURL: URL {
#if canImport(UIKit)
        return nowPlayingURLs.filter(UIApplication.shared.canOpenURL).first!
#endif
    }

    var nowPlayingURLs: [URL] {
        var urls = [URL(string: "https://apps.apple.com/app/apple-store/id1596487035?pt=670995&ct=click-for-sonos&mt=8")!]
        if musicService == .apple, let url = URL(string:"nowplaying://musicSong?i=\(trackID)") {
            urls.insert(url, at: 0)
        } else if musicService == .spotify, let isrc = metadata?.ISRC, let url = URL(string:"nowplaying://song?isrc=\(isrc)") {
            urls.insert(url, at: 0)
        }
        return urls
    }
}
