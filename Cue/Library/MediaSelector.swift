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
    @State private var tabProviders = TabProviderStore.shared
    
    var body: some View {
        Menu {
            ForEach(MediaSearchService.allCases, id: \.self) { service in
                if coreFeatures.enabledServices(service).wrappedValue, service.isBrowseSupported {
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
            Divider()
            // The provider on screen can be pinned as a tab of its own from
            // here — the one place on iPhone, which has no sidebar, that
            // is already about providers.
            if tabProviders.contains(browseMediaService) {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    tabProviders.remove(browseMediaService)
                } label: {
                    Label("Remove \(browseMediaService.title) from Tabs", systemImage: "minus.circle")
                }
            } else if browseMediaService.canBeTab, coreFeatures.isEnabled(browseMediaService) {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    tabProviders.add(browseMediaService)
                } label: {
                    Label("Add \(browseMediaService.title) to Tabs", systemImage: "plus.circle")
                }
            }
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                router.presentedSheet = .customizeTabs
            } label: {
                Label("Customize Tabs…", systemImage: "slider.horizontal.3")
            }
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
            guard let service = MediaSearchService.allCases.first(where: { coreFeatures.isEnabled($0) }) else { return }
            browseMediaService = service
        }
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}

