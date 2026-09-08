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

struct MediaSelector: View {
    @AppStorage(AppStorageKeys.browseMediaService) private var browseMediaService: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined
    
    var closeInspector: (() -> Void)? = nil
    
    @Environment(Router.self) private var router
    @State private var coreFeatures = CoreFeatures.shared
    
    var body: some View {
        Menu {
            ForEach(MediaSearchService.supported, id: \.self) { service in
                if coreFeatures.enabledServices(service).wrappedValue, service.isBrowseSupported {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        browseMediaService = service
                    } label: {
                        HStack {
                            Text(service.title)
                            // Pre-tinted: the menu ignores `tint` and any
                            // foreground style on the row's image.
                            service.menuImage
                        }
                    }
                    .tag(service)
                }
            }
            Divider()
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                router.presentedSheet = .settings(destination: .servicePreferenceScreen)
            } label: {
                Label("Settings…", systemImage: "gear")
            }
        } label: {
            browseMediaService.iconForMusicService
                .frame(width: 24, height: 24)
                .toolbarBackground(in: .circle)
        }
        .contentShape(.rect)
        .onChange(of: coreFeatures.features) {
            if coreFeatures.isEnabled(browseMediaService) {
                return
            }
            guard let service = MediaSearchService.supported.first(where: { coreFeatures.isEnabled($0) }) else { return }
            browseMediaService = service
        }
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}

