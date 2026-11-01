import MusicKit
import MusicSearchKit
import SonosKit
import SwiftUI

/// Onboarding's services page: where the music is. Every service Cue plays
/// is a row (`ServiceChoiceRow`) chosen with a tap, and what's chosen is
/// what Search, Browse and the tabs offer afterwards (`WelcomeScreen`).
/// Choosing Apple Music is what asks for Apple Music access, never sooner
/// (`AppleMusicPermission`); a server set up in Cue opens its sign-in here;
/// Plex signs in on the page after.
struct ServicesStep: View {
    /// What was chosen when the page was last left, for coming back to it.
    var initial: Set<MediaSearchService>? = nil
    var advance: (_ chosen: Set<MediaSearchService>) -> Void

    @Environment(\.scenePhase) private var scenePhase

    @State private var chosen: Set<MediaSearchService> = []
    @State private var appleStatus = MusicAuthorization.currentStatus
    @State private var isAskingApple = false
    /// Apple Music turned down before: a tap explains, and offers Settings.
    @State private var showsAppleMusicOff = false
    /// The server whose sign-in is up, and the one it was opened for, which
    /// the sheet's dismissal reads after `signingIn` has gone back to nil.
    @State private var signingIn: SignIn?
    @State private var lastSignIn: MediaSearchService?
    @State private var didSeed = false
    @State private var contentIn = false

    private struct SignIn: Identifiable {
        let service: MediaSearchService
        var id: String { service.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Where’s your music?")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Pick the services you use. Cue plays them here and on your speakers.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.top, 56)
            .padding(.bottom, 20)
            .opacity(contentIn ? 1 : 0)
            .offset(y: contentIn ? 0 : 14)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(MediaSearchService.supported.enumerated()), id: \.element) { index, service in
                        ServiceChoiceRow(
                            service: service,
                            accessory: accessory(for: service)
                        ) {
                            tap(service)
                        }
                        .opacity(contentIn ? 1 : 0)
                        .offset(y: contentIn ? 0 : 18)
                        .animation(
                            .spring(response: 0.55, dampingFraction: 0.85).delay(0.1 + Double(index) * 0.05),
                            value: contentIn
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                // A column on iPad and the Mac rather than rows across the
                // whole window.
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 12)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 24)
                }
            }
            // The rows' own colours are hierarchical; here they're on the
            // dark mesh whatever the app's appearance.
            .environment(\.colorScheme, .dark)

            VStack(spacing: 10) {
                PrimaryPillButton(title: "Continue") {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    advance(chosen)
                }
                Text("You can change this any time in Settings.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .opacity(contentIn ? 1 : 0)
            .offset(y: contentIn ? 0 : 24)
        }
        .onAppear {
            seedChoices()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { contentIn = true }
        }
        // Back from Settings, where Apple Music access may have been turned on.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            let status = MusicAuthorization.currentStatus
            if status != appleStatus {
                appleStatus = status
                if status == .authorized { choose(.apple) }
            }
        }
        .sheet(item: $signingIn, onDismiss: finishSignIn) { signIn in
            signInSheet(for: signIn.service)
        }
        .alert("Apple Music Access Is Off", isPresented: $showsAppleMusicOff) {
            Button("Open Settings", action: openMusicPrivacySettings)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Allow Cue to use Media & Apple Music in Settings to play your library.")
        }
    }

    // MARK: - Rows

    private func accessory(for service: MediaSearchService) -> ServiceChoiceRow.Accessory {
        if service == .apple, isAskingApple { return .progress }
        return .check(chosen.contains(service))
    }

    /// Set up already, so there's nothing to sign in to or allow.
    private func isReady(_ service: MediaSearchService) -> Bool {
        switch service {
        case .apple: appleStatus == .authorized
        case .plex: PlexAuthenticator.shared.authToken != nil
        case .tuneIn: true
        default: service.isConfiguredInCue == true
        }
    }

    /// Nothing is chosen for anyone: what's picked is what they tapped.
    /// Coming back to the page, what was picked before.
    private func seedChoices() {
        guard !didSeed else { return }
        didSeed = true
        chosen = initial ?? []
    }

    // MARK: - Choosing

    private func tap(_ service: MediaSearchService) {
        if chosen.contains(service) {
            HapticManager.shared.fireHaptic(.selection)
            chosen.remove(service)
            return
        }
        switch service {
        case .apple:
            chooseAppleMusic()
        case .plex, .tuneIn:
            choose(service)
        default:
            if isReady(service) {
                choose(service)
            } else {
                HapticManager.shared.fireHaptic(.selection)
                lastSignIn = service
                signingIn = SignIn(service: service)
            }
        }
    }

    private func choose(_ service: MediaSearchService) {
        HapticManager.shared.fireHaptic(.selection)
        chosen.insert(service)
    }

    /// The system's alert, asked for here and nowhere earlier. Turned down
    /// before, it can only be turned on in Settings, which a tap explains
    /// rather than the row's line changing.
    private func chooseAppleMusic() {
        switch appleStatus {
        case .authorized:
            choose(.apple)
        case .notDetermined:
            isAskingApple = true
            Task {
                let status = await AppleMusicPermission.ask()
                appleStatus = status
                isAskingApple = false
                if status == .authorized {
                    HapticManager.shared.fireHaptic(.notification(.success))
                    chosen.insert(.apple)
                } else {
                    HapticManager.shared.fireHaptic(.notification(.warning))
                }
            }
        default:
            HapticManager.shared.fireHaptic(.notification(.warning))
            showsAppleMusicOff = true
        }
    }

    // MARK: - Sign-in

    @ViewBuilder
    private func signInSheet(for service: MediaSearchService) -> some View {
        switch service {
        case .subsonic: SubsonicManagementView()
        case .audiobookshelf: AudiobookshelfManagementView()
        case .files: FilesManagementView()
        default: EmptyView()
        }
    }

    /// Signed in, the service is chosen; closed without, it stays as it was.
    private func finishSignIn() {
        guard let service = lastSignIn else { return }
        lastSignIn = nil
        if isReady(service) {
            HapticManager.shared.fireHaptic(.notification(.success))
            chosen.insert(service)
        }
    }

    private func openMusicPrivacySettings() {
        #if canImport(UIKit)
        #if targetEnvironment(macCatalyst)
        let address = "x-apple.systempreferences:com.apple.preference.security?Privacy_Media"
        #else
        let address = UIApplication.openSettingsURLString
        #endif
        if let url = URL(string: address) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

#Preview {
    ZStack {
        MeshBackground().ignoresSafeArea()
        ServicesStep { _ in }
    }
    .withEnvironments()
}
