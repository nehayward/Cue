import Kingfisher
import SwiftUI
import SonosKitMini
import MusicKit
import MusicSearchKit

struct ThumbnailView: View {
    var device: SonosDevice
    var size: Size = .medium
    
    var body: some View {
        VStack {
            KFImage.url(device.track.sonosAlbumArtURL)
                .resizable()
                .setProcessor(DownsamplingImageProcessor(size: Size.medium.size))
                .interpolation(.medium)
                .placeholder {
                    Rectangle()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.background.secondary)
                        .shadow(radius: 2)
                        .overlay {
                            if device.track.sonosAlbumArtURL == nil {
                                Image(systemName: "music.note")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: size.size.height/2, height: size.size.height/2)
                                    .bold()
                                    .transaction { transaction in
                                        transaction.animation = nil
                                    }
                            } else {
                                ProgressView()
                            }
                        }
                }
                .diskCacheExpiration(.days(1))
                .resizable()
                .aspectRatio(contentMode: .fit)
#if DEBUG && SCREENSHOT
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .foregroundStyle(.ultraThinMaterial)
                }
#endif
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 2)
        .overlay(alignment: .bottomTrailing) {
            GeometryReader { proxy in
                device.track.musicService.icon
                    .frame(width: proxy.size.width * 0.2, height:  proxy.size.width * 0.2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(4)
            }
        }
        .overlay {
            if device.groupIsMuted {
                Image(systemName: "speaker.slash.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.primary)
                    .frame(width: 24, height: 24)
                    .bold()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .foregroundStyle(.ultraThinMaterial)
                    }
                    .clipped()
                    .animation(.spring, value: device.groupIsMuted)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

extension ThumbnailView {
    enum Size {
        case small
        case medium
        
        var size: CGSize {
            switch self {
            case .small:
                CGSize(width: 40, height: 40)
            case .medium:
                CGSize(width: 100, height: 100)
            }
        }
    }
}

//#Preview("Empty") {
//    ContentArtworkView(track: .constant(Track(trackID: "", name: "", TVMode: false)))
//        .environment(SonosService.shared)
//}
//
//#Preview("Dua Lipa") {
//    ContentArtworkView(track: .constant(Track(trackID: "6wf7Yu7cxBSPrRlWeSeK0Q", musicService: .spotify)))
//        .environment(SonosService.shared)
//}
//
//#Preview("White Background") {
//    ContentArtworkView(track: .constant(Track(trackID: "204669559", musicService: .apple)))
//        .environment(SonosService.shared)
//
//}
//
//#Preview("Dark Album") {
//    ContentArtworkView(track: .constant(Track(trackID: "7sjuNUjWtSqhbxJ3RAUffm", musicService: .spotify)))
//        .environment(SonosService.shared)
//}
//
