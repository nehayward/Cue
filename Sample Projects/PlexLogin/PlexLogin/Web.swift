import SwiftUI
import SafariServices
import AuthenticationServices

struct SFSafariViewWrapper: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: UIViewControllerRepresentableContext<Self>) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SFSafariViewWrapper>) {
        return
    }
}

struct SafariViewTest: View {
    @State private var token: String?
    @State private var showSafari = false
    @State private var code = ""
    @State private var clientID = UUID().uuidString
    @State private var sessionID = UUID().uuidString
    private let authenticator = Authenticator()

    var body: some View {
        VStack {
            if let token = token {
                Text("Authenticated! Token: \(token)")
            } else {
                Button("Authenticate with Plex") {
                    print("https://app.plex.tv/auth/#?clientID=\(clientID)&code=\(code)")
                    authenticateWithPlex()
                }
//                .sheet(isPresented: $showSafari) {
//                    let url = URL(string: "https://app.plex.tv/auth#?clientID=\(clientID)&code=\(code)".trimmingCharacters(in: .whitespacesAndNewlines))!
//                    SFSafariViewWrapper(url: url)
//                }
//
//                Link(destination: URL(string: "https://app.plex.tv/auth#?clientID=\(clientID)&code=\(code)".trimmingCharacters(in: .whitespacesAndNewlines))!) {
//                    Text("https://app.plex.tv/auth#?clientID=\(clientID)&code=\(code)".trimmingCharacters(in: .whitespacesAndNewlines))
//                }
            }
        }
        .task {
            startMonitor()
        }
    }

    func startMonitor() {
        Task {
            let request = createPin()
            guard let (data, response) = try? await URLSession.shared.data(for: request) else {
                return
            }
            print(String(decoding: data, as: UTF8.self))
            let pinResponse = try! JSONDecoder().decode(PinResponse.self, from: data)
            print(pinResponse)
            print(clientID)
            print(pinResponse.clientIdentifier)
            clientID = pinResponse.clientIdentifier
            code = pinResponse.code
            let token = try? await pollForAuthToken(id: pinResponse.id.description)
            print(token)
            showSafari = false
        }
    }

    func createPin() -> URLRequest {
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

    func fetchPin(id: String) async throws -> PinResponse? {
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

    func pollForAuthToken(id: String, interval: TimeInterval = 5.0) async throws -> String {
        while true {
            do {
                if let pinResponse = try await fetchPin(id: id), let authToken = pinResponse.authToken {
                    Task { @MainActor in
                        authenticator.session?.cancel()
                    }
                    return authToken
                }
                print("Empty")
            } catch {
                print("Polling error: \(error)")
            }

            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    func authenticateWithPlex() {
        authenticator.authenticate(with: clientID, code: code) { success in

        }
    }
}


struct PinResponse: Codable {
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


class Authenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    var session: ASWebAuthenticationSession?
    private var completion: ((Bool) -> Void)?

    func authenticate(with clientID: String, code: String, completion: @escaping (Bool) -> Void) {
        self.completion = completion
        
        let authURL = URL(string: "https://app.plex.tv/auth/#?clientID=\(clientID)&code=\(code)")!
        session = ASWebAuthenticationSession(url: authURL, callback: .customScheme("me")) { callbackURL, error in

        }
        session?.presentationContextProvider = self
        session?.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

