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
    
    var authenticationComplete: (() -> Void)?

    var body: some View {
        Group {
            if !musicSearchService.isPlexAuthorized {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    PlexAuthenticator.shared.authenticate()
                } label: {
                    VStack(spacing: 12) {
                        Text("Authorize Plex")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .bold()
                            .foregroundStyle(.accent)
                        Text("Please use the Plex account on your existing Sonos and have remote access enabled.")
                            .font(.caption)
                        
                        if let url = plexAuthenticator.authorizationURL {
                            Link(destination: url) {
                                Text(url.absoluteString)
                                    .textSelection(.enabled)
                                    .font(.caption)
                            }
                            .foregroundStyle(.accent)
                        }
                    }
                }
                .onAppear {
                    plexAuthenticator.restartMonitor()
                }
                .onDisappear {
                    plexAuthenticator.stopMonitor()
                }
            }

            if musicSearchService.isPlexAuthorized && musicSearchService.plexServerID == nil {
                Section {
                    if servers.isEmpty {
                        ProgressView()
                            .opacity(isLoading ? 1 : 0)
                    } else {
                        ForEach(servers, id: \.clientIdentifier) { server in
                            Button {
                                HapticManager.shared.fireHaptic(.buttonPress)
                                musicSearchService.plexServerID = server.clientIdentifier
                                isLoading = true
                                Task {
                                    servers = await musicSearchService.getPlexServers()
                                    isLoading = false
                                }
                                authenticationComplete?()
                            } label: {
                                HStack {
                                    if server.clientIdentifier == musicSearchService.plexServerID  {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(server.name)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Choose Plex Server")
                        .foregroundStyle(.secondary)
                        .task {
                            isLoading = true
                            servers = await musicSearchService.getPlexServers()
                            isLoading = false
                        }
                        .listRowSeparator(.hidden)
                }
                .frame(maxWidth: .infinity)
                .fontDesign(.rounded)
            }
        }
        .listRowSeparator(.hidden)
        .onDisappear {
            plexAuthenticator.stopMonitor()
        }
    }
}
