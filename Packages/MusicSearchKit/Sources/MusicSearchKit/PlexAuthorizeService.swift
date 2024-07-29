import Foundation
import AuthenticationServices

@MainActor
public final class PlexAuthenticator: NSObject {
    private var clientID = UUID().uuidString
    private var pollTask: Task<Void, Error>?
    private var session: ASWebAuthenticationSession?

    public static var shared = PlexAuthenticator()

    public var authToken: String? {
        get {
            UserDefaults.standard.string(forKey: "com.clic.plexToken")
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: "com.clic.plexToken")
        }
    }

#if os(iOS) || os(macOS) || os(visionOS)
    private func authenticate(with clientID: String) async {
        guard let code = await startMonitor() else { return }
        let authURL = URL(string: "https://app.plex.tv/auth/#?clientID=\(clientID)&code=\(code)")!
        session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: nil) { [weak self] callbackURL, error in
            if error != nil {
                self?.pollTask?.cancel()
            }
        }
        session?.presentationContextProvider = self
        session?.start()
    }

    public func authenticate() {
        Task {
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
        print(pinResponse.clientIdentifier)
        pollForAuthToken(id: pinResponse.id.description)
        return pinResponse.code
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

#if os(iOS) || os(macOS)
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
