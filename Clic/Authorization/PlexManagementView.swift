import CloudStorage
import Defaults
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit

struct PlexManagementView: View {
    @Environment(\.dismiss) private var dismiss

    private var musicSearchService = MusicSearchService.shared
    @State private var servers: [PlexServer] = []
    @State private var libraries: [String: [PlexLibrarySection]] = [:]
    @State private var isLoading = false
    @State private var isReloadingLibraries = false
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

                    // Library selection
                    if musicSearchService.isPlexAuthorized {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Connection Type")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            Text("Choose how to connect to your Plex server:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            ForEach(PlexAPI.ConnectionPreference.allCases, id: \.self) { preference in
                                Button(action: {
                                    HapticManager.shared.fireHaptic(.buttonPress)
                                    musicSearchService.plexConnectionPreference = preference
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(preference.displayName)
                                                    .font(.body.bold())
                                                    .foregroundStyle(.primary)
                                                
                                                if preference == .nonLocal {
                                                    Text("(Recommended)")
                                                        .font(.caption)
                                                        .foregroundStyle(.accent)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.accent.opacity(0.1)))
                                                }
                                            }
                                            
                                            Text(preference.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if musicSearchService.plexConnectionPreference == preference {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.accent)
                                                .transition(.scale.combined(with: .opacity))
                                        }
                                    }
                                    .padding()
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Text("Choose Music Library")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            if isLoading || isReloadingLibraries {
                                VStack {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                    if isReloadingLibraries {
                                        Text("Reloading libraries...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
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
                                VStack(spacing: 12) {
                                    ForEach(servers, id: \.clientIdentifier) { server in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text([server.name, server.device].compactMap { $0 }.joined(separator: ", "))
                                                .font(.headline)
                                                .padding(.horizontal)
                                            
                                            if let serverLibraries = libraries[server.name] {
                                                if serverLibraries.isEmpty {
                                                    Text("No music libraries found")
                                                        .font(.subheadline)
                                                        .foregroundStyle(.secondary)
                                                        .padding(.horizontal)
                                                } else {
                                                    ForEach(serverLibraries, id: \.id) { library in
                                                        Button(action: {
                                                            HapticManager.shared.fireHaptic(.buttonPress)
                                                            musicSearchService.plexServerID = server.clientIdentifier
                                                            musicSearchService.plexLibrarySelectionID = library.key
                                                        }) {
                                                            HStack {
                                                                Text(library.title)
                                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                                
                                                                if musicSearchService.plexLibrarySelectionID == library.key {
                                                                    Image(systemName: "checkmark.circle.fill")
                                                                        .foregroundStyle(.accent)
                                                                        .transition(.scale.combined(with: .opacity))
                                                                }
                                                            }
                                                            .padding()
                                                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                                                        }
                                                        .buttonStyle(.plain)
                                                        .animation(.spring(duration: 0.3), value: musicSearchService.plexLibrarySelectionID)
                                                    }
                                                }
                                            } else {
                                                ProgressView()
                                                    .frame(maxWidth: .infinity)
                                                    .padding()
                                            }
                                        }
                                    }
                                }
                                .task {
                                    await withTaskGroup(of: Void.self) { group in
                                        for server in servers {
                                            group.addTask {
                                                let musicLibraries = await PlexAPI().getMusicLibraries(server: server)
                                                await MainActor.run {
                                                    libraries[server.name] = musicLibraries
                                                }
                                            }
                                        }
                                    }
                                }
                                if UIApplication.shared.isRunningInTestFlightEnvironment() {
                                    LoggerView()
                                }
                            }
                        }
                        .task {
                            servers = await musicSearchService.getPlexServers()
                            await withTaskGroup(of: Void.self) { group in
                                for server in servers {
                                    group.addTask {
                                        let musicLibraries = await PlexAPI().getMusicLibraries(server: server)
                                        await MainActor.run {
                                            libraries[server.name] = musicLibraries
                                        }
                                    }
                                }
                            }
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
