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

struct BrowseScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    @AppStorage(AppStorageKeys.browseMediaService) private var browseMediaService: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    @State private var router = Router()
    @State private var alertService = AlertService()
    @State private var isLoaded: Bool = false
    @State private var coreFeatures = CoreFeatures()

    var body: some View {
        Group {
            switch browseMediaService {
            case .apple:
                AppleLibraryBrowseScreen()
            case .plex:
                PlexBrowseScreen()
            case .spotify:
                Text("Coming Soon…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .library:
                LibraryBrowseScreen()
            default:
                NavigationStack {
                    EmptyView()
                        .addDismiss(action: dismiss.callAsFunction)
                }
            }
        }
        .contentMargins(.bottom, 80, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            VStack {
                Menu {
                    ForEach(MediaSearchService.allCases, id: \.self) { service in
                        // MARK: Add Spotify
                        if coreFeatures.enabledServices(service).wrappedValue, [MediaSearchService.apple, MediaSearchService.library, MediaSearchService.plex].contains(service) {
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
                        router.presentedSheet = .settings
                    } label: {
                        Text("Customize in Settings…")
                    }
                } label: {
                    browseMediaService.iconForMusicService
                        .frame(width: 24, height: 24)
                }
                .popoverTip(AppTip.mediaService)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding()

                MiniPlayerView()
            }
        }
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }


}

#Preview {
    BrowseScreen()
        .withEnvironments()
}

