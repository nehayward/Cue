//

import SwiftUI

@main
struct SpotifyLoginApp: App {

    var body: some Scene {        
        WindowGroup {
            @State var simple = SpotifySimple()

            ContentView()
                .onOpenURL { url in
                    simple.isAuthorized = true
                    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
                        print("Error: Invalid URL.")
                        return 
                    }

                    // Find the query item named "code"
                    let code = components.queryItems?.first { $0.name == "code" }?.value
                    simple.code = code  ?? ""
                    print(code)
                }
                .environment(simple)
        }
    }
}
