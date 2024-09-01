//
import PlexKit
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
        .onAppear {
            let info = Plex.ClientInfo(clientIdentifier: UUID().uuidString)

            let client = Plex(sessionConfiguration: .default, clientInfo: info)

            client.request(
                // plex.tv endpoints are namespaced under `Plex.ServiceRequest`.
                Plex.ServiceRequest.SimpleAuthentication(
                    username: "nehayward",
                    password: "jamnyX-9cufnu-koxmuj"
                )
            ) { result in
                switch result {
                case .success(let response):
                    print("Hello, \(response.user.title)!")
                    print("Your authentication token is \(response.user.authenticationToken)")
                case .failure(let error):
                    print("An error occurred: \(error)")
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
