import SwiftUI
import SonosKit
import MusicSearchKit

struct OpenInServiceView: View {
    var item: PlayableContent

    var body: some View {
        if let url = item.serviceWebURL {
            let service = item.content.service
            Link(destination: url) {
                Label {
                    Text("Open in \(service.title)")
                } icon: {
                    service.image
                        .frame(width: 24, height: 24)
                }
            }
            .tint(service.brandColor)
        }
    }
}
