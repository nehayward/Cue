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
    
    var closeInspector: (() -> Void)? = nil
    
    @State private var router = Router()
    @State private var alertService = AlertService()
    @State private var isLoaded: Bool = false
    @State private var coreFeatures = CoreFeatures.shared
    
    var body: some View {
        Group {
            switch browseMediaService {
            case .apple:
                AppleLibraryBrowseScreen()
            case .plex:
                PlexBrowseScreen()
            case .spotify:
                SpotifyPlaylistScreen(showMediaSelector: true)
            case .library:
                LibraryBrowseScreen()
            default:
                NavigationStack {
                    EmptyView()
                        .addDismiss(action: dismiss.callAsFunction)
                }
            }
        }
        .contentMargins(.bottom, 120, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
#if !targetEnvironment(macCatalyst)
                MiniPlayerView()
                    .offset(y: MiniPlayerManger.shared.offset)
#endif
        }
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .ignoresSafeArea(.keyboard, edges: .bottom)
#if !targetEnvironment(macCatalyst)
        .addDismiss {
            dismiss()
            closeInspector?()
        }
#endif
        .onChange(of: coreFeatures.features) {
            if coreFeatures.isEnabled(browseMediaService) {
                return
            }
            guard let service = MediaSearchService.allCases.first(where: { coreFeatures.isEnabled($0) }) else { return }
            browseMediaService = service
        }
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

#Preview {
    BrowseScreen()
        .withEnvironments()
}

