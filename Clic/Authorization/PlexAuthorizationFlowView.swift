import CloudStorage
import Defaults
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit

struct PlexAuthorizationFlowView: View {
    @State var musicSearchService = MusicSearchService()
    @State private var servers: [PlexServer] = []
    @State private var isLoading = false
    @State private var plexAuthenticator = PlexAuthenticator.shared

    var body: some View {
        Group {
            if !musicSearchService.isPlexAuthorized {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    PlexAuthenticator.shared.authenticate()
                } label: {
                    VStack {
                        Text("Authorize Plex")
                            .frame(maxWidth: .infinity)
                        Text("Please use the Plex account on your existing Sonos")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.accent)
                .onAppear {
                    plexAuthenticator.restartMonitor()
                }
                .onDisappear {
                    plexAuthenticator.stopMonitor()
                }

                if let url = plexAuthenticator.authorizationURL {
                    Link(destination: url) {
                        Text(url.absoluteString)
                            .textSelection(.enabled)
                    }
                }
            }

            if musicSearchService.isPlexAuthorized && musicSearchService.plexServerID == nil {
                VStack {
                    Text(Image(systemName: "checkmark.circle.fill")).foregroundStyle(.green).bold() + Text(" Authorized").bold()
                    ForEach(servers, id: \.clientIdentifier) { server in
                        Button {
                            HapticManager.shared.fireHaptic(.buttonPress)
                            musicSearchService.plexServerID = server.clientIdentifier
                        } label: {
                            VStack {
                                Text(server.name)
                                    .frame(maxWidth: .infinity)
//                                ForEach(server.externalURIs, id: \.self) { uri in
//                                    Text(uri)
//                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.accent)
                    }
                    Text("Select Plex Server")
                        .foregroundStyle(.secondary)
                        .task {
                            isLoading = true
                            servers = await musicSearchService.getPlexServers()
                            isLoading = false
                        }
                }
                .fontDesign(.rounded)
                .overlay {
                    ProgressView()
                        .opacity(isLoading ? 1 : 0)
                }
            }
        }
        .listRowSeparator(.hidden)
        .onDisappear {
            plexAuthenticator.stopMonitor()
        }
    }
}
