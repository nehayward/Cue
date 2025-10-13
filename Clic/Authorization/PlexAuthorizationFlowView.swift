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
    @State private var isReloadingLibraries = false
    @State private var plexAuthenticator = PlexAuthenticator.shared
    
    var authenticationComplete: (() -> Void)?

    var body: some View {
        VStack {
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
                connectionPreferenceView
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
                .frame(maxWidth: .infinity, alignment: .center)
            
            if isLoading || isReloadingLibraries {
                VStack {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                    Text(isReloadingLibraries ? "Reloading libraries..." : "Loading servers...")
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
                                            isLoading = true
                                            Task {
                                                servers = await musicSearchService.getPlexServers()
                                                isLoading = false
                                                authenticationComplete?()
                                            }
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
                                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
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
                                let musicLibraries = await PlexAPI.shared.getMusicLibraries(server: server)
                                await MainActor.run {
                                    libraries[server.name] = musicLibraries
                                }
                            }
                        }
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
    
    private var connectionPreferenceView: some View {
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
                    
                    // Reload libraries when connection preference changes
                    Task {
                        isReloadingLibraries = true
                        libraries.removeAll()
                        servers = await musicSearchService.getPlexServers()
                        await withTaskGroup(of: Void.self) { group in
                            for server in servers {
                                group.addTask {
                                    let musicLibraries = await PlexAPI.shared.getMusicLibraries(server: server)
                                    await MainActor.run {
                                        libraries[server.name] = musicLibraries
                                    }
                                }
                            }
                        }
                        isReloadingLibraries = false
                    }
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
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)
                .animation(.spring(duration: 0.3), value: musicSearchService.plexConnectionPreference)
            }
        }
        .padding(.horizontal)
    }
}
