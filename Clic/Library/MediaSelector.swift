import Analytics
import CloudStorage
import MusicSearchKit
import Defaults
import NukeUI
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults
import TipKit

struct MediaSelector: View {
    @AppStorage(AppStorageKeys.browseMediaService) private var browseMediaService: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined
    
    var closeInspector: (() -> Void)? = nil
    
    @Environment(Router.self) private var router
    @State private var coreFeatures = CoreFeatures.shared
    
    var body: some View {
        Menu {
            ForEach(MediaSearchService.allCases, id: \.self) { service in
                if coreFeatures.enabledServices(service).wrappedValue, [
                        .apple,
                        .library,
                        .plex,
                        .spotify,
                        .soundcloud
                    ]
                    .contains(service) {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        browseMediaService = service
                    } label: {
                        HStack {
                            Text(service.title)
                            service.image
                        }
                    }
                    .tint(service.brandColor)
                    .tag(service)
                }
            }
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                router.presentedSheet = .settings(destination: .servicePreferenceScreen)
            } label: {
                Label("Settings…", systemImage: "gear")
            }
        } label: {
            // iconOnly Label fixes the iOS 26 toolbar hit target. iconOnly
            // re-tints the icon with the control color, so re-apply the brand
            // color on the Label; keep the frame on the image for sizing.
            Label {
                Text(browseMediaService.title)
            } icon: {
                browseMediaService.iconForMusicService
                    .frame(width: 24, height: 24)
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(browseMediaService.brandColor.gradient)
            .toolbarBackground(in: .circle)
        }
        .contentShape(Rectangle())
        .popoverTip(AppTip.libraryMediaService)
        .onChange(of: coreFeatures.features) {
            if coreFeatures.isEnabled(browseMediaService) {
                return
            }
            guard let service = MediaSearchService.allCases.first(where: { coreFeatures.isEnabled($0) }) else { return }
            browseMediaService = service
        }
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}

