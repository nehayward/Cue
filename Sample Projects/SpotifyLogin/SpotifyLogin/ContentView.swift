//
import AuthenticationServices
import SwiftUI

struct ContentView: View {
    @Environment(SpotifySimple.self) var simple
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        Form {
            if !simple.isAuthorized {
                Link(destination: simple.authorize(), label: {
                    Text("Link")
                })
            } else {
                Text(simple.codeVerifier)
                    .textSelection(.enabled)
                Text(simple.code)
                    .textSelection(.enabled)
            }

            Button("Sign In") {
                Task {
                    do {
                        if #available(iOS 17.4, *) {
                            let urlWithToken = try await webAuthenticationSession.authenticate(using: simple.authorize(), callback: .customScheme("testing"), preferredBrowserSession: .ephemeral, additionalHeaderFields: [:])
                            print(urlWithToken)

                        } else {
                            // Fallback on earlier versions
                        }
    //                    try await signIn(using: urlWithToken) // defined elsewhere
                    } catch {
                        print(error.localizedDescription)
                        // code to handle authentication errors
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
