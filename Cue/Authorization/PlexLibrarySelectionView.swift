import CloudStorage
import Defaults
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit

struct PlexLibrarySelectionView: View {
    private var musicSearchService = MusicSearchService.shared
    @State private var servers: [PlexServer] = []
    @State private var libraries: [String: [PlexLibrarySection]] = [:]
    @State private var isLoading = false
    @State private var isReloadingLibraries = false
    
    var body: some View {
        if musicSearchService.isPlexAuthorized, musicSearchService.plexServerID == nil {
            Section {
                ForEach(PlexAPI.ConnectionPreference.allCases, id: \.self) { preference in
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        musicSearchService.plexConnectionPreference = preference
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(preference.displayName)
                                        .font(.body.bold())
                                        .foregroundStyle(.primary)
                                    
                                    if preference == .auto {
                                        Text("Recommended")
                                            .font(.caption.smallCaps())
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
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.accent)
                                .opacity(musicSearchService.plexConnectionPreference == preference  ? 1 : 0)
                        }
                        
                    }
                    .listRowSeparator(.hidden)
                    .buttonStyle(.plain)
                }
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
                                                        let libraryFilter = GenericFilter(filter: library)
                                                        libraryFilter.isFiltered = true
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
                    if UIApplication.shared.isRunningInTestFlightEnvironment() {
                        LoggerView()
                    }
                }
            }
        } else {
            EmptyView()
        }
    }
    
}

#Preview {
    List {
        PlexLibrarySelectionView()
    }
}
