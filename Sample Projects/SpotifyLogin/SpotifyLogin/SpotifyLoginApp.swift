//

import SwiftUI

@main
struct SpotifyLoginApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL(perform: { url in
                    print(url)
                })
        }
    }
}
