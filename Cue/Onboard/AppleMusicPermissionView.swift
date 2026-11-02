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
            Label("Connect Apple Music", systemImage: "apple.logo")
        } description: {
            Text(musicSearchService.appleMusicAuthorizationStatus == .denied
                 ? "Apple Music access is off. Turn it on in Settings to search your library and the catalog."
                 : "Allow access to search your library and the Apple Music catalog.")
        } actions: {
            switch musicSearchService.appleMusicAuthorizationStatus {
            case .notDetermined, .authorized:
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    Task {
                        await AppleMusicPermission.ask()
                        appleMusicAuthorized = musicSearchService.getMusicAuthorization()
                    }
                } label: {
                    Text("Allow Access")
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
                    Text("Open Settings")
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
