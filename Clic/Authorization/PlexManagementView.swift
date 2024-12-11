import CloudStorage
import Defaults
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit

struct PlexManagementView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var musicSearchService = MusicSearchService.shared
    @State private var servers: [PlexServer] = []
    @State private var isLoading = false
    @State private var plexAuthenticator = PlexAuthenticator.shared

    var body: some View {
        NavigationStack {
            Form {
                if !musicSearchService.isPlexAuthorized {
                    Section {
                        Button {
                            HapticManager.shared.fireHaptic(.buttonPress)
                            PlexAuthenticator.shared.authenticate()
                        } label: {
                            Text("Authorize Plex")
                        }
                        .tint(.accent)
                        .onAppear {
                            plexAuthenticator.restartMonitor()
                        }
                        .onDisappear {
                            plexAuthenticator.stopMonitor()
                        }
                    } footer: {
                        VStack {
                            Text("Please use the Plex account on your existing Sonos")
                            if let url = plexAuthenticator.authorizationURL {
                                Link(destination: url) {
                                    Text(url.absoluteString)
                                        .multilineTextAlignment(.leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                
                if musicSearchService.isPlexAuthorized {
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
                }
                
                if musicSearchService.isPlexAuthorized {
                    Section {
                        Button {
                            HapticManager.shared.fireHaptic(.buttonPress)
                            musicSearchService.plexServerID = nil
                            PlexAuthenticator.shared.authToken = nil
                            PlexAuthenticator.shared.authenticate()
                        } label: {
                            Text("Reauthorize Plex")
                        }
                        .foregroundStyle(.red)
                    } footer: {
                        Text("Please use the Plex account on your existing Sonos and have remote access enabled.")
                    }
                }
            }
            .headerProminence(.increased)
            .listStyle(.grouped)
            .listRowSeparator(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Text("Plex")
                        Image(systemName: musicSearchService.isPlexAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(musicSearchService.isPlexAuthorized ? .green : .red)
                    }
                }
            }
            .addDismiss(action: dismiss.callAsFunction)
        }
    }
}

#Preview {
    PlexManagementView()
}
