import Defaults
import MusicKit
import MusicSearchKit
import SwiftUI

/// Browse with no service it can show (radio alone was chosen in
/// onboarding, or everything else switched off): the services it could
/// show, as onboarding offers them (`ServiceChoiceRow`). Apple Music asks for
/// access here, the servers open their sign-in, which switches them on, and
/// Browse moves to the one set up (`BrowseScreen.fallBackFromDisabledService`).
/// Without it Browse stayed on the Apple library, switched off, and its first
/// read put up Apple Music's alert.
struct BrowseServicePrompt: View {
    @AppStorage(AppStorageKeys.browseMediaService) private var browseMediaService: MediaSearchService = .apple
    @Environment(\.dismiss) private var dismiss
    @State private var router = Router.browse
    @State private var isAskingApple = false

    private var services: [MediaSearchService] {
        MediaSearchService.supported.filter(\.isBrowseSupported)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.house.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                            .accessibilityHidden(true)
                        Text("Nothing to Browse Yet")
                            .font(.title2.bold())
                        Text("Add a service to see your music here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    VStack(spacing: 10) {
                        ForEach(services, id: \.self) { service in
                            ServiceChoiceRow(
                                service: service,
                                accessory: service == .apple && isAskingApple ? .progress : .disclosure
                            ) {
                                add(service)
                            }
                        }
                    }
                    .frame(maxWidth: 460)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
            .fontDesign(.rounded)
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsToolbarButton()
                        .environment(router)
                }
            }
            .withAppRouter()
        }
        .environment(router)
    }

    private func add(_ service: MediaSearchService) {
        HapticManager.shared.fireHaptic(.selection)
        guard service == .apple else {
            if let sheet = service.managementSheet {
                router.presentedSheet = sheet
            }
            return
        }
        switch MusicAuthorization.currentStatus {
        case .notDetermined:
            isAskingApple = true
            Task {
                let status = await AppleMusicPermission.ask()
                isAskingApple = false
                if status == .authorized { useAppleMusic() }
            }
        case .authorized:
            useAppleMusic()
        default:
            #if targetEnvironment(macCatalyst)
            let address = "x-apple.systempreferences:com.apple.preference.security?Privacy_Media"
            #else
            let address = UIApplication.openSettingsURLString
            #endif
            if let url = URL(string: address) {
                UIApplication.shared.open(url)
            }
        }
    }

    private func useAppleMusic() {
        HapticManager.shared.fireHaptic(.notification(.success))
        CoreFeatures.shared.enabledServices(.apple).wrappedValue = true
        browseMediaService = .apple
    }
}
