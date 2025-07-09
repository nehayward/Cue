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
                    .tag(service)
                }
            }
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                router.presentedSheet = .settings(destination: .servicePreferenceScreen)
            } label: {
                Text("Customize in Settings…")
            }
        } label: {
            browseMediaService.iconForMusicService
                .frame(width: 24, height: 24)
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

