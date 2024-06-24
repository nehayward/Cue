import SwiftUI
import SonosKit
import MusicSearchKit

struct OpenInServiceView: View {
    var item: PlayableContent

    var body: some View {
        if let openInURL = item.content.location {
            if item.content.service == .apple {
                Link(destination: openInURL) {
                    Label("Open in Apple Music…", systemImage: "apple.logo")
                }
            }
            if item.content.service == .spotify {
                Link(destination: openInURL) {
                    Label {
                        Text("Open in Spotify…")
                    } icon: {
                        MusicService.spotify.image
                    }
                }
            }

            if item.content.service == .tidal {
                Link(destination: openInURL) {
                    Label {
                        Text("Open in Tidal…")
                    } icon: {
                        MediaSearchService.tidal.icon
                    }
                }
            }
        }
    }
}
