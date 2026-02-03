import SwiftUI
import SonosKit
import MusicSearchKit

struct OpenInServiceView: View {
    var item: PlayableContent

    var body: some View {
        if let openInURL = item.content.location {
            if item.content.service == .apple {
                Link(destination: openInURL) {
                    Label {
                        Text("Open in Apple")
                    } icon: {
                        MusicService.apple.image
                            .tint(MusicService.apple.brandColor.gradient)
                            .foregroundStyle(MusicService.apple.brandColor.gradient)
                            .frame(width: 24, height: 24)
                    }
                }
            }
            
            if item.content.service == .spotify {
                Link(destination: openInURL) {
                    Label {
                        Text("Open in Spotify")
                    } icon: {
                        MusicService.spotify.image
                            .tint(MusicService.spotify.brandColor.gradient)
                            .foregroundStyle(MusicService.spotify.brandColor.gradient)
                            .frame(width: 24, height: 24)
                    }
                }
            }

            if item.content.service == .tidal {
                Link(destination: openInURL) {
                    Label {
                        Text("Open in Tidal")
                    } icon: {
                        MediaSearchService.tidal.icon
                            .tint(MusicService.tidal.brandColor.gradient)
                            .foregroundStyle(MusicService.tidal.brandColor.gradient)
                            .frame(width: 24, height: 24)
                    }
                }
            }
            
            if item.content.service == .soundcloud {
                Link(destination: openInURL) {
                    Label {
                        Text("Open in SoundCloud")
                    } icon: {
                        MediaSearchService.soundcloud.iconForMusicService
                    }
                }
            }
        }
    }
}
