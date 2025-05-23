import Foundation
import AuthenticationServices


@Observable
public final class PlexAuthenticator: NSObject {
    public var authorizationURL: URL?
    @ObservationIgnored private var clientID = UUID().uuidString
    @ObservationIgnored private var pinID: String?
    @ObservationIgnored private var pollTask: Task<Void, Error>?
    @ObservationIgnored private var session: ASWebAuthenticationSession?

    public static var shared = PlexAuthenticator()

//    public var authToken: String? = "KSAM-R573sKNdDdk2i-G"
    public var authToken: String? {
        didSet {
            UserDefaults.standard.setValue(authToken, forKey: "com.clic.plexToken")
        }
    }
    
    public override init() {
        super.init()
        authToken = UserDefaults.standard.string(forKey: "com.clic.plexToken")
        print(#file)
    }

#if os(iOS) || targetEnvironment(macCatalyst) || os(visionOS)
    @MainActor
    private func authenticate(with clientID: String) async {
        guard let code = await startMonitor() else { return }
        let authURL = URL(string: "https://app.plex.tv/auth/#?clientID=\(clientID)&code=\(code)")!
        authorizationURL = authURL
        session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: nil) { callbackURL, error in

        }
        session?.presentationContextProvider = self
        session?.start()
    }

    public func authenticate() {
        Task {
            authToken = nil
            authorizationURL = nil
            await authenticate(with: clientID)
        }
    }
#endif

    func startMonitor() async -> String? {
        let request = createPin()
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            return nil
        }
        let pinResponse = try! JSONDecoder().decode(PinResponse.self, from: data)
        pinID = pinResponse.id.description
        pollForAuthToken(id: pinResponse.id.description)
        return pinResponse.code
    }

    public func restartMonitor() {
        if let pinID {
            pollForAuthToken(id: pinID)
        }
    }

    public func stopMonitor() {
        authorizationURL = nil
        pollTask?.cancel()
    }

    private func createPin() -> URLRequest {
        let url = URL(string: "https://plex.tv/api/v2/pins?strong=1")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("iPhone", forHTTPHeaderField: "X-Plex-Device")
        request.setValue("iOS", forHTTPHeaderField: "X-Plex-Platform")
        request.setValue("Clic", forHTTPHeaderField: "X-Plex-Product")
        request.setValue(clientID, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue("iPhone", forHTTPHeaderField: "X-Plex-Device-Name")
        request.setValue("https://assets.clic.dance/Icon.png", forHTTPHeaderField: "X-Plex-Device-Icon")
        return request
    }

    private func fetchPin(id: String) async throws -> PinResponse? {
        let url = URL(string: "https://plex.tv/api/v2/pins/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("iPhone", forHTTPHeaderField: "X-Plex-Device")
        request.setValue("iOS", forHTTPHeaderField: "X-Plex-Platform")
        request.setValue("Clic", forHTTPHeaderField: "X-Plex-Product")
        request.setValue(clientID, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("iPhone", forHTTPHeaderField: "X-Plex-Device-Name")
        print(request)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let pinResponse = try JSONDecoder().decode(PinResponse.self, from: data)
        return pinResponse
    }

    private func pollForAuthToken(id: String) {
        pollTask?.cancel()
        #if !os(tvOS)
        pollTask = Task {
            while true {
                do {
                    if let pinResponse = try await self.fetchPin(id: id), let authToken = pinResponse.authToken {
                        Task { @MainActor in
                            session?.cancel()
                        }
                        self.authToken = authToken
                        pollTask?.cancel()
                    }
                }
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        #endif
    }

    private struct PinResponse: Codable {
        let id: Int
        let code: String
        let product: String
        let trusted: Bool
        let qr: String
        let clientIdentifier: String
        let expiresIn: Int
        let createdAt: String
        let expiresAt: String
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
