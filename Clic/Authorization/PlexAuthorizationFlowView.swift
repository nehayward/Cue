import CloudStorage
import Defaults
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit

struct PlexAuthorizationFlowView: View {
    var musicSearchService = MusicSearchService.shared
    @State private var servers: [PlexServer] = []
    @State private var libraries: [String: [PlexLibrarySection]] = [:]
    @State private var isLoading = false
    @State private var plexAuthenticator = PlexAuthenticator.shared
    
    var authenticationComplete: (() -> Void)?

    var body: some View {
        Group {
            if plexAuthenticator.authToken == nil {
                VStack(alignment: .center, spacing: 16) {
                    Text("Connect Your Plex Account")
                        .font(.title2.bold())
                    
                    Text("Make sure you're using the Plex account linked to your Sonos system and that remote access is enabled.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    
                    Link(destination: URL(string: "https://support.plex.tv/articles/200289506-remote-access/")!) {
                         HStack(spacing: 4) {
                             Text("Remote Access Setup")
                             Image(systemName: "arrow.up.forward")
                         }
                     }
                     .foregroundStyle(.accent)
                     .buttonStyle(.plain)
                    
                    if let url = plexAuthenticator.authorizationURL {
                        Link(destination: url) {
                            Text(url.absoluteString)
                                .font(.footnote)
                                .foregroundStyle(.blue)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .textSelection(.enabled)
                    }
                    
                    Button(action: {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        plexAuthenticator.authenticate()
                    }) {
                        Text("Authorize Plex")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.accent)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accent)
                }
                .onAppear {
                    plexAuthenticator.restartMonitor()
                }
                .onDisappear {
                    plexAuthenticator.stopMonitor()
                }
                .multilineTextAlignment(.center)
            }

            if musicSearchService.isPlexAuthorized && musicSearchService.plexServerID == nil {
                serverSelectionView
            }
        }
        .listRowSeparator(.hidden)
        .onDisappear {
            plexAuthenticator.stopMonitor()
        }
    }
    
    private var serverSelectionView: some View {
        VStack(alignment: .center, spacing: 16) {
            Text("Choose Music Library")
                .font(.title2.bold())
            
            if isLoading {
                VStack {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                    Text("Loading servers...")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
            } else if servers.isEmpty {
                Text("No Plex servers found.")
                    .font(.headline)
                
                Text("Make sure your Plex Media Server is online and your account has remote access enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Link("Open Plex Web App", destination: URL(string: "https://app.plex.tv/")!)
                    .font(.caption)
                    .foregroundStyle(.accent)
            } else {
                VStack(spacing: 12) {
                    ForEach(servers, id: \.clientIdentifier) { server in
                        if let serverLibraries = libraries[server.name] {
                            ForEach(serverLibraries, id: \.id) { library in
                                Button(action: {
                                    HapticManager.shared.fireHaptic(.buttonPress)
                                    musicSearchService.plexServerID = server.clientIdentifier
                                    musicSearchService.plexLibrarySelectionID = library.key
                                    isLoading = true
                                    Task {
                                        servers = await musicSearchService.getPlexServers()
                                        isLoading = false
                                        authenticationComplete?()
                                    }
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(library.title)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            
                                            if musicSearchService.plexLibrarySelectionID == library.key {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.accent)
                                                    .transition(.scale.combined(with: .opacity))
                                            }
                                        }
                                        
                                        Text([server.name, server.device].compactMap { $0 }.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .transition(.opacity)
                                    }
                                    .padding()
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                                }
                                .buttonStyle(.plain)
                                .animation(.spring(duration: 0.3), value: musicSearchService.plexLibrarySelectionID)
                            }
                        }
                    }
                }
                .task {
                    for server in servers {
                        libraries[server.name] = await PlexAPI().getMusicLibraries(server: server)
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
        .task {
            isLoading = true
            servers = await musicSearchService.getPlexServers()
            isLoading = false
        }
    }
}
