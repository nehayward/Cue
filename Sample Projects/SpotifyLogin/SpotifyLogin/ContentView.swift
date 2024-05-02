//

import SwiftUI

struct ContentView: View {
    @Environment(SpotifySimple.self) var simple

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
        }
    }
}

#Preview {
    ContentView()
}
