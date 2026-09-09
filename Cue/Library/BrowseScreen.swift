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

struct BrowseScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Environment(SonosService.self) private var sonosService
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService
    @Environment(MiniPlayerManger.self) private var miniPlayerManager

    @AppStorage(AppStorageKeys.browseMediaService) private var browseMediaService: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined
    
    var closeInspector: (() -> Void)? = nil

    @State private var router = Router.browse
    @State private var isLoaded: Bool = false
    @State private var coreFeatures = CoreFeatures.shared
    @State private var offline = OfflineMode.shared

    private var showAlert: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    
    var body: some View {
        VStack {
            // Browse is the phone's home, so it is where offline shows what's
            // on this device; the provider screens below have nothing to
            // show with no network.
            if offline.isActive {
                OfflineBrowseScreen()
            } else {
                browseScreen
            }
        }
        .contentMargins(.top, EdgeInsets(), for: .scrollContent)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .withAlert(enabled: showAlert)
#if !targetEnvironment(macCatalyst)
        .safeArea(edge: .bottom) {
            if !miniPlayerManager.hidden {
                MiniPlayerView()
                    .geometryGroup()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
#endif
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: coreFeatures.features) {
            fallBackFromDisabledService()
        }
        // The stored choice can be a service this build no longer offers.
        .onAppear(perform: fallBackFromDisabledService)
        .overlay(
            Button {
                closeInspector?()
            } label: {
                EmptyView()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .frame(width: 0, height: 0)
            .hidden()
        )
    }
}

private extension BrowseScreen {
    /// The chosen provider's browse screen.
    @ViewBuilder
    var browseScreen: some View {
        switch browseMediaService {
        case .apple:
            AppleLibraryBrowseScreen()
        case .plex:
            PlexBrowseScreen()
        case .spotify:
            SpotifyLibraryScreen()
        case .library:
            LibraryBrowseScreen()
        case .soundcloud:
            SoundCloudBrowseScreen()
        case .deezer:
            DeezerBrowseScreen()
        case .sonosRadio:
            SonosRadioBrowseScreen()
        case .pandora:
            PandoraBrowseScreen()
        case .subsonic:
            SubsonicBrowseScreen()
        case .files:
            FilesBrowseScreen()
        default:
            NavigationStack {
                EmptyView()
                    .addDismiss(action: dismiss.callAsFunction)
            }
        }
    }
}

private extension BrowseScreen {
    /// Moves off a browse service that is disabled — or gone — to the first
    /// one still on, so the screen never sits on a provider it can't show.
    func fallBackFromDisabledService() {
        if coreFeatures.isEnabled(browseMediaService) {
            return
        }
        guard let service = MediaSearchService.supported.first(where: { coreFeatures.isEnabled($0) }) else { return }
        browseMediaService = service
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}

