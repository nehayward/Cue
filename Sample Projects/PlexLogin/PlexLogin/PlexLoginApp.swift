//

import SwiftUI
import PlexKit

@main
struct PlexLoginApp: App {
    var body: some Scene {
        WindowGroup {
            SafariViewTest()
                .onAppear {
                    let info = Plex.ClientInfo(clientIdentifier: UUID().uuidString)

                    let client = Plex(sessionConfiguration: .default, clientInfo: info)
                    
                }
//            Test2()
//                .onOpenURL { url in
//                    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
//                        print("Error: Invalid URL.")
//                        return
//                    }
//
//                    print(components)
//                }
        }
        
    }
}
