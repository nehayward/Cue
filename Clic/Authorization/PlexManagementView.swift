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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if plexAuthenticator.authToken == nil {
                        VStack(alignment: .center, spacing: 16) {
                            Text("Connect Your Plex Account")
                                .font(.title2.bold())
                            
                            Text("Make sure you're using the Plex account linked to your Sonos system and that remote access is enabled.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            
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

                    // Server selection
                    if musicSearchService.isPlexAuthorized {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Choose Plex Server")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else if servers.isEmpty {
                                VStack(alignment: .center, spacing: 8) {
                                    Text("No Plex servers found.")
                                        .font(.body.bold())

                                    Text("Make sure your Plex Media Server is online and remote access is enabled.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Link("Open Plex Web App", destination: URL(string: "https://app.plex.tv/")!)
                                        .font(.caption)
                                        .foregroundStyle(.accent)
                                }
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                            } else {
                                ForEach(servers, id: \.clientIdentifier) { server in
                                    Button(action: {
                                        HapticManager.shared.fireHaptic(.buttonPress)
                                        musicSearchService.plexServerID = server.clientIdentifier
                                        isLoading = true
                                        Task {
                                            servers = await musicSearchService.getPlexServers()
                                            isLoading = false
                                        }
                                    }) {
                                        HStack {
                                            if server.clientIdentifier == musicSearchService.plexServerID {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.accent)
                                            }
                                            Text(server.name)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding()
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .task {
                            isLoading = true
                            servers = await musicSearchService.getPlexServers()
                            isLoading = false
                        }
                    }

                    // Reauth option
                    if musicSearchService.isPlexAuthorized {
                        VStack(alignment: .leading, spacing: 12) {
                            Button(role: .destructive) {
                                HapticManager.shared.fireHaptic(.buttonPress)
                                musicSearchService.plexServerID = nil
                                plexAuthenticator.authToken = nil
                                plexAuthenticator.authenticate()
                            } label: {
                                Label("Reauthorize Plex", systemImage: "arrow.clockwise.circle")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(.red.opacity(0.1))
                                    .foregroundStyle(.red)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            Text("Use the Plex account from your Sonos system with remote access enabled.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Plex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Text("Plex")
                        Image(systemName: musicSearchService.isPlexAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(musicSearchService.isPlexAuthorized ? .green : .red)
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }
}

#Preview {
    PlexManagementView()
}
