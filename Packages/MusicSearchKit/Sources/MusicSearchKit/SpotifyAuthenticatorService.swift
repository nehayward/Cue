import Foundation
import AuthenticationServices

@MainActor
public final class SpotifyAuthenticatorService: NSObject {
    private var session: ASWebAuthenticationSession?

    public static var shared = PlexAuthenticator()
    private let key = "com.clic.spotifyToken"

    // TODO: Use Keychain
    public var authToken: String? {
        get {
            UserDefaults.standard.string(forKey: key)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: key)
        }
    }

#if os(iOS) || os(macOS)
    private func authenticate() async {
        let authURL = URL(string: "https://app.plex.tv/auth/#?clientID=&code=")!
        session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: nil) { callbackURL, error in }
        session?.presentationContextProvider = self
        session?.start()
    }
#endif
}

#if os(iOS) || os(macOS)
extension SpotifyAuthenticatorService: ASWebAuthenticationPresentationContextProviding {
    public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
#endif
