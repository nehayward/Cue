import Foundation
import AuthenticationServices

/// Signs in to plex.tv with the PIN flow Plex asks third-party apps to use:
/// Cue creates a PIN, the user approves it on Plex's own sign-in page, and Cue
/// polls the PIN until it carries an account token.
///
/// The page opens in an `ASWebAuthenticationSession`, which is Safari. It
/// shares Safari's cookies, so someone already signed in to plex.tv there only
/// has to approve Cue, and Password AutoFill, password managers and Sign in
/// with Apple or Google all work on it. A password form in Cue could offer
/// none of that for plex.tv, and would fail every account without a password.
///
/// Plex only forwards to http(s) addresses when it's done, so the session never
/// calls back with a URL; the poll closes it as soon as the token lands.
@Observable
public final class PlexAuthenticator: NSObject {
    /// Plex's sign-in page for the current PIN, while a sign-in is under way.
    /// The sign-in screens offer it for finishing in the browser instead.
    public private(set) var authorizationURL: URL?
    /// Set from the tap until the sign-in page is up. Creating the PIN is a
    /// round trip to plex.tv, and the button should show it's working.
    public private(set) var isStartingSignIn = false
    /// Why the last sign-in couldn't start, for the sign-in screens to show.
    public private(set) var signInError: String?

    /// Identifies this install to Plex. Kept across launches: Plex lists each
    /// client identifier that signs in under Authorized Devices, and a fresh
    /// one per launch added another "Cue" there with every sign-in.
    @ObservationIgnored private var clientID = PlexAuthenticator.storedClientID()
    @ObservationIgnored private var pinID: Int?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var session: ASWebAuthenticationSession?

    public static var shared = PlexAuthenticator()

    private static let product = "Cue"
    private static let clientIDKey = "com.cue.plexClientID"

    @ObservationIgnored
    public var authToken: String? {
        get {
            access(keyPath: \.authToken)
            return UserDefaults.standard.string(forKey: "com.cue.plexToken")
        }
        set {
            withMutation(keyPath: \.authToken) {
                UserDefaults.standard.set(newValue, forKey: "com.cue.plexToken")
            }
        }
    }

    public override init() {
        super.init()
    }

    private static func storedClientID() -> String {
        if let stored = UserDefaults.standard.string(forKey: clientIDKey), !stored.isEmpty {
            return stored
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: clientIDKey)
        return id
    }

#if os(iOS) || targetEnvironment(macCatalyst) || os(visionOS)
    /// Creates a PIN and opens Plex's sign-in page for it.
    public func authenticate() {
        Task { @MainActor in
            await startSignIn()
        }
    }

    @MainActor
    private func startSignIn() async {
        guard !isStartingSignIn else { return }
        isStartingSignIn = true
        signInError = nil
        defer { isStartingSignIn = false }

        stopMonitor()
        session?.cancel()
        session = nil
        pinID = nil
        authorizationURL = nil

        let pin: PinResponse
        do {
            pin = try await createPin()
        } catch {
            signInError = "Couldn't reach Plex. Check your connection and try again."
            return
        }
        guard let url = authURL(code: pin.code) else {
            signInError = "Couldn't open the Plex sign-in page."
            return
        }
        pinID = pin.id
        authorizationURL = url
        pollForAuthToken(id: pin.id)

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { _, _ in
            // Only runs when the sheet closes, by the user or by the poll.
            // The poll keeps going either way, so a sign-in finished in the
            // browser instead still lands.
        }
        session.presentationContextProvider = self
        // Safari's cookies and saved logins, not a blank private browser.
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        if !session.start() {
            self.session = nil
            signInError = "Couldn't open the Plex sign-in page. Try opening it in your browser."
        }
    }
#endif

    /// Resumes polling a sign-in that's still under way, for a sign-in screen
    /// that comes back on screen.
    public func restartMonitor() {
        guard authToken == nil, let pinID else { return }
        pollForAuthToken(id: pinID)
    }

    /// Stops polling. The PIN is kept, so `restartMonitor` can pick it up.
    public func stopMonitor() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - PIN

    /// Plex's sign-in page for a PIN. Its parameters go in the fragment, and
    /// `context[device][product]` is the app name the page shows.
    private func authURL(code: String) -> URL? {
        let parameters = [
            ("clientID", clientID),
            ("code", code),
            ("context[device][product]", Self.product)
        ]
        let query = parameters
            .map { "\(Self.encoded($0.0))=\(Self.encoded($0.1))" }
            .joined(separator: "&")
        return URL(string: "https://app.plex.tv/auth#?\(query)")
    }

    private static func encoded(_ string: String) -> String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return string.addingPercentEncoding(withAllowedCharacters: unreserved) ?? string
    }

    private func createPin() async throws -> PinResponse {
        var request = pinRequest(url: URL(string: "https://plex.tv/api/v2/pins?strong=1")!)
        request.httpMethod = "POST"
        request.setValue("https://assets.cue.dance/Icon.png", forHTTPHeaderField: "X-Plex-Device-Icon")
        return try await send(request)
    }

    private func fetchPin(id: Int) async throws -> PinResponse {
        try await send(pinRequest(url: URL(string: "https://plex.tv/api/v2/pins/\(id)")!))
    }

    private func pinRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("iPhone", forHTTPHeaderField: "X-Plex-Device")
        request.setValue("iOS", forHTTPHeaderField: "X-Plex-Platform")
        request.setValue(Self.product, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(clientID, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue("iPhone", forHTTPHeaderField: "X-Plex-Device-Name")
        return request
    }

    private func send(_ request: URLRequest) async throws -> PinResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw URLError(.badServerResponse)
        }
        // Plex answers 404 once a PIN has expired.
        if status == 404 { throw PinError.expired }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(PinResponse.self, from: data)
    }

    private func pollForAuthToken(id: Int) {
        pollTask?.cancel()
        #if !os(tvOS)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    if let token = try await self.fetchPin(id: id).authToken {
                        await self.finishSignIn(token: token)
                        return
                    }
                } catch PinError.expired {
                    await self.pinExpired(id: id)
                    return
                } catch {
                    // A request dropped while the phone switches apps or
                    // networks. The next tick tries again.
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        #endif
    }

    @MainActor
    private func finishSignIn(token: String) {
        authToken = token
        pinID = nil
        authorizationURL = nil
        signInError = nil
        pollTask = nil
        #if !os(tvOS)
        session?.cancel()
        session = nil
        #endif
    }

    @MainActor
    private func pinExpired(id: Int) {
        guard pinID == id else { return }
        pinID = nil
        authorizationURL = nil
        pollTask = nil
    }

    private enum PinError: Error {
        case expired
    }

    /// Only the fields the flow reads, so a change elsewhere in Plex's
    /// response can't fail the decode.
    private struct PinResponse: Decodable {
        let id: Int
        let code: String
        let authToken: String?
    }
}

#if os(iOS) || targetEnvironment(macCatalyst)
extension PlexAuthenticator: ASWebAuthenticationPresentationContextProviding {
    public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
#endif

#if os(visionOS)
extension PlexAuthenticator: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication
            .shared
            .connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .last ?? ASPresentationAnchor()
    }
}
#endif
