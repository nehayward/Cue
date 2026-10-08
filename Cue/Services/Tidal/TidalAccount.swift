import AuthenticationServices
import Foundation
import MusicSearchKit
import Observation
import OSLog
import UIKit
#if canImport(Auth) && canImport(EventProducer)
import Auth
import EventProducer
#endif

/// The TIDAL account Cue plays as, signed in through TIDAL's own SDK (the
/// Auth module, `tidal-sdk-ios`): TIDAL's login page in a Safari sheet, the
/// authorization code with PKCE, and the tokens kept in the keychain by the
/// SDK, which refreshes them itself.
///
/// The one account does three jobs: it's who TIDAL's Player plays as on this
/// device (`TidalPlayer`), it reads the user's collection and searches their
/// country's catalog (`TidalAPI.userToken`), and it's what makes TIDAL a
/// service Cue offers at all. Signed out, TIDAL is off: a speaker with TIDAL
/// linked in the Sonos app could play it, but Cue only offers services this
/// device plays too.
///
/// Full songs depend on TIDAL as well as the account: until TIDAL raises the
/// app's access tier, the Player plays 30-second previews, and says so
/// (`PlaybackContext.previewReason`).
///
/// The SDK is linked into the iOS and Mac apps only, so everything here is
/// behind `canImport`; elsewhere TIDAL is simply unavailable.
@Observable
final class TidalAccount: NSObject {
    static let shared = TidalAccount()

    /// Cue's app on the TIDAL Developer Platform (developer.tidal.com ▸
    /// Dashboard). Empty leaves TIDAL out of the app. The app there needs
    /// `redirectURI` listed exactly, and the `scopes` turned on.
    static let clientID = ""
    /// Where TIDAL's login page sends the code. A scheme of its own, caught
    /// by the sign-in sheet, so it never reaches the app's own links.
    static let redirectURI = "\(callbackScheme)://login"
    private static let callbackScheme = "cue-tidal"
    /// Account details (the country the catalog answers from), the
    /// collection and playlists, search, and playback.
    private static let scopes: Set<String> = ["user.read", "collection.read", "playlists.read", "search.read", "playback"]
    /// The keychain entry the SDK keeps the tokens under.
    private static let credentialsKey = "dance.cue.tidal"

    /// Whether this build can sign in to TIDAL at all: the SDK is linked and
    /// a client id is set.
    static var isAvailable: Bool {
        #if canImport(Auth) && canImport(EventProducer)
        return !clientID.isEmpty
        #else
        return false
        #endif
    }

    /// Whether a TIDAL user is signed in. Read from the SDK's token store at
    /// launch and kept here, since views read it on every update.
    private(set) var isSignedIn = false
    private(set) var isSigningIn = false
    /// Why the last sign-in didn't finish, for the sign-in sheet to show.
    private(set) var signInError: String?
    /// Why the last TIDAL song played here came as a 30-second preview, or
    /// nil when it played in full. Set by the player (`TidalPlayer`).
    var previewNotice: String?

    @ObservationIgnored private var isConfigured = false
    @ObservationIgnored private var session: ASWebAuthenticationSession?
    private static let log = Logger(subsystem: "dance.cue", category: "tidal")

    private override init() {
        super.init()
        // Whatever reaches for the account first — a restored queue asking
        // whether its TIDAL rows can play, say — finds it set up.
        configure()
    }

    /// Sets up the SDK's Auth and event modules, once, and reads whether
    /// someone is already signed in. Runs when the account is first used;
    /// cheap after that, so anything that needs the SDK calls it first too.
    func configure() {
        #if canImport(Auth) && canImport(EventProducer)
        guard Self.isAvailable, !isConfigured else { return }
        isConfigured = true
        TidalAuth.shared.config(config: AuthConfig(
            clientId: Self.clientID,
            credentialsKey: Self.credentialsKey,
            scopes: Self.scopes
        ))
        // The play reports TIDAL counts plays and pays artists by. Nothing
        // for advertising.
        TidalEventSender.shared.config(EventConfig(
            credentialsProvider: TidalAuth.shared,
            maxDiskUsageBytes: 1_000_000,
            blockedConsentCategories: [.targeting]
        ))
        isSignedIn = TidalAuth.shared.isUserLoggedIn
        TidalAPI.userToken = {
            // Asked for every request: the SDK refreshes an expired token
            // itself, so a kept copy would only go stale.
            guard TidalAuth.shared.isUserLoggedIn,
                  let credentials = try? await TidalAuth.shared.getCredentials(),
                  credentials.userId != nil else { return nil }
            return credentials.token
        }
        #endif
    }

    /// Opens TIDAL's login page and, once it hands back a code, signs in
    /// with it. Turns TIDAL on in search and the library when it lands.
    @MainActor
    func signIn() async {
        #if canImport(Auth) && canImport(EventProducer)
        configure()
        guard Self.isAvailable, !isSigningIn else { return }
        signInError = nil
        guard let url = TidalAuth.shared.initializeLogin(redirectUri: Self.redirectURI, loginConfig: LoginConfig()) else {
            signInError = "Couldn’t open the Tidal sign-in page."
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let callback = try await openLoginPage(url)
            try await TidalAuth.shared.finalizeLogin(loginResponseUri: callback.absoluteString)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            Self.log.error("TIDAL sign-in failed: \(error.localizedDescription, privacy: .public)")
            signInError = "Tidal didn’t sign you in. Try again in a moment."
            return
        }
        isSignedIn = TidalAuth.shared.isUserLoggedIn
        if isSignedIn {
            CoreFeatures.shared.enabledServices(.tidal).wrappedValue = true
        } else {
            signInError = "Tidal didn’t sign you in. Try again in a moment."
        }
        #endif
    }

    /// Forgets the account: the tokens go from the keychain, playback on
    /// this device stops if it was TIDAL's, and TIDAL leaves search and the
    /// library.
    @MainActor
    func signOut() {
        #if canImport(Auth) && canImport(EventProducer)
        guard isConfigured else { return }
        LocalPlaybackService.shared.signedOutOfTidal()
        do {
            try TidalAuth.shared.logout()
        } catch {
            Self.log.error("TIDAL sign-out failed: \(error.localizedDescription, privacy: .public)")
        }
        isSignedIn = TidalAuth.shared.isUserLoggedIn
        signInError = nil
        CoreFeatures.shared.enabledServices(.tidal).wrappedValue = false
        #endif
    }

    /// Shows the login page and waits for TIDAL to send the browser to
    /// `redirectURI`, which carries the code (or the error).
    @MainActor
    private func openLoginPage(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let resume = ResumeOnce(continuation)
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(Self.callbackScheme)) { [weak self] callbackURL, error in
                Task { @MainActor in self?.session = nil }
                if let callbackURL {
                    resume.returning(callbackURL)
                } else {
                    resume.throwing(error ?? ASWebAuthenticationSessionError(.canceledLogin))
                }
            }
            session.presentationContextProvider = self
            // Safari's cookies and saved logins, so someone signed in to
            // TIDAL in Safari only has to approve Cue.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                self.session = nil
                resume.throwing(ASWebAuthenticationSessionError(.presentationContextInvalid))
            }
        }
    }
}

extension TidalAccount: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}

/// Resumes a continuation the first time only: the sign-in sheet's
/// completion and a failed start can both try.
private final class ResumeOnce: @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }

    func returning(_ url: URL) {
        take()?.resume(returning: url)
    }

    func throwing(_ error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<URL, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let taken = continuation
        continuation = nil
        return taken
    }
}
