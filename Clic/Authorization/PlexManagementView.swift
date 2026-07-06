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
}

#Preview {
    PlexManagementView()
}
