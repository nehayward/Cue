import SwiftUI
import MusicSearchKit
import Defaults
import SonosKit

struct AppleMusicPermissionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MusicSearchService.self) private var musicSearchService: MusicSearchService
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    var body: some View {
        ContentUnavailableView {
            Label("Improved Search", systemImage: "magnifyingglass")
        } description: {
            Text("Enhance search with search suggestions.")
        } actions: {
            switch musicSearchService.appleMusicAuthorizationStatus {
            case .notDetermined, .authorized:
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    Task {
                        await musicSearchService.requestMusicAuthorization()
                        appleMusicAuthorized = musicSearchService.getMusicAuthorization()
                    }
                } label: {
                    Text("Continue")
                }
                .buttonStyle(.bordered)
                .bold()
            case .denied:
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    #if targetEnvironment(macCatalyst)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media") {
                        UIApplication.shared.open(url)
                    }
                    #else
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    #endif
                } label: {
                    Text("Allow in System Setting")
                }
                .buttonStyle(.bordered)
                .bold()
            }
        }
        .onAppear {
            appleMusicAuthorized = musicSearchService.getMusicAuthorization()
        }

    }
}

#Preview {
    AppleMusicPermissionsView()
        .environment(MusicSearchService())
}
