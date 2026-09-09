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
            List {
                if plexAuthenticator.authToken == nil {
                    signInSection
                } else {
                    Section {
                        PlexConnectionPicker(selection: Binding(
                            get: { musicSearchService.plexConnectionPreference },
                            set: { musicSearchService.plexConnectionPreference = $0 }
                        ))
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } header: {
                        Text("Connection Type")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .task(id: musicSearchService.plexConnectionPreference) {
                        servers.removeAll()
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
                    }
                
                    Section {
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
                            VStack(spacing: 16) {
                                ForEach(servers, id: \.clientIdentifier) { server in
                                    VStack(alignment: .leading, spacing: 12) {
                                        if let serverLibraries = libraries[server.name] {
                                            if serverLibraries.isEmpty {
                                                HStack {
                                                    Text([server.name, server.device].compactMap { $0 }.joined(separator: ", "))
                                                        .font(.headline)
                                                    Spacer()
                                                    Text("No music libraries")
                                                        .font(.subheadline)
                                                        .foregroundStyle(.secondary)
                                                }
                                            } else {
                                                HStack {
                                                    Text([server.name, server.device].compactMap { $0 }.joined(separator: ", "))
                                                        .font(.headline)
                                                
                                                    Spacer()
                                                
                                                    // Menu on the right
                                                    Menu {
                                                        ForEach(serverLibraries, id: \.id) { library in
                                                            Button(action: {
                                                                HapticManager.shared.fireHaptic(.buttonPress)
                                                                musicSearchService.plexServerID = server.clientIdentifier
                                                                musicSearchService.plexLibrarySelectionID = library.key
                                                            }) {
                                                                HStack {
                                                                    Text(library.title)
                                                                    if musicSearchService.plexLibrarySelectionID == library.id {
                                                                        Image(systemName: "checkmark")
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    } label: {
                                                        HStack(spacing: 6) {
                                                            Text(serverLibraries.first(where: { $0.key == musicSearchService.plexLibrarySelectionID })?.title ?? "Select Library")
                                                                .font(.subheadline)
                                                            Image(systemName: "chevron.up.chevron.down")
                                                                .imageScale(.small)
                                                        }
                                                        .foregroundStyle(.accent)
                                                    }
                                                }
                                            }
                                        } else {
                                            HStack {
                                                Text([server.name, server.device].compactMap { $0 }.joined(separator: ", "))
                                                    .font(.headline)
                                                Spacer()
                                                ProgressView()
                                            }
                                        }
                                    }
                                    .padding(.bottom, 8)
                                }
                            }
                            .task {
                                await withTaskGroup { group in
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
                            if UIApplication.shared.isRunningInTestFlightEnvironment() {
                                LoggerView()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Text("Plex")
                        Image(systemName: musicSearchService.isPlexAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(musicSearchService.isPlexAuthorized ? AnyShapeStyle(.green.gradient) : AnyShapeStyle(.red))
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }

    /// Shown until the account is linked. Without it the sheet went straight
    /// to the server picker and reported "No Plex servers found" to someone
    /// who simply hadn't signed in yet. The monitor polls for the PIN the
    /// browser sign-in approves, so it runs only while this section is up.
    private var signInSection: some View {
        Section {
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

                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    plexAuthenticator.authenticate()
                } label: {
                    Text("Authorize Plex")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, 8)
        }
        .listRowSeparator(.hidden)
        .onAppear {
            plexAuthenticator.restartMonitor()
        }
        .onDisappear {
            plexAuthenticator.stopMonitor()
        }
    }
}

#Preview {
    PlexManagementView()
}
