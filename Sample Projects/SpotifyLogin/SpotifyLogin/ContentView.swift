//

import SwiftUI

struct ContentView: View {
    
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            Link("Login", destination: Spotify().authorize())
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
