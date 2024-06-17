//import SwiftUI
//import AuthenticationServices
//
//
//class Authenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
//    private var session: ASWebAuthenticationSession?
//    private var completion: ((Bool) -> Void)?
//
//    func authenticate(with clientID: String, redirectURI: String, completion: @escaping (Bool) -> Void) {
//        self.completion = completion
//
//        let authURL = URL(string: "https://app.plex.tv/auth/#?clientID=516CAF9A-1971-559D-BD08-8DA9EBC97F67&code=7ovtzdqs82nfm9hmzn6qnnl5z&redirect_uri=me")!
//
//
//        session = ASWebAuthenticationSession(url: authURL, callback: .customScheme("me")) { callbackURL, error in
//            
//        }
//        session?.presentationContextProvider = self
//        session?.start()
//    }
//
//    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
//        return UIApplication.shared.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
//    }
//}
//
//struct ContentView: View {
//    @State private var isAuthenticated = false
//    private let authenticator = Authenticator()
//
//    var body: some View {
//        VStack {
//            if isAuthenticated {
//                Text("Authenticated!")
//            } else {
//                Button("Authenticate with Plex") {
//                    authenticateWithPlex()
//                }
//            }
//        }
//    }
//
//    func authenticateWithPlex() {
//        let clientID = "YOUR_CLIENT_ID"
//        let redirectURI = "me"
//
//        authenticator.authenticate(with: clientID, redirectURI: redirectURI) { success in
//            DispatchQueue.main.async {
//                self.isAuthenticated = success
//            }
//        }
//    }
//}
//
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}
