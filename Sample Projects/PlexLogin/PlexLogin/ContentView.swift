import SwiftUI
import AuthenticationServices

struct WebAuthenticationSessionExample: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        Button("Sign In") {
            Task {
                do {
                    let urlWithToken = try await webAuthenticationSession.authenticate(using: URL(string: "https://plex.tv/link")!, callback: .customScheme("testing"), preferredBrowserSession: .ephemeral, additionalHeaderFields: [:])
                    print(urlWithToken)
//                    try await signIn(using: urlWithToken) // defined elsewhere
                } catch {
                    print(error.localizedDescription)
                    // code to handle authentication errors
                }
            }
        }
    }
}
