import CloudStorage
import Defaults
import MusicSearchKit
import OrderedCollections
import SwiftUI
import SonosKit

struct PlexManagementView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var musicSearchService = MusicSearchService()
    @State private var servers: [PlexServer] = []
    @State private var isLoading = false
    @State private var plexAuthenticator = PlexAuthenticator.shared

    var body: some View {
        NavigationStack {
            List {
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

                if musicSearchService.isPlexAuthorized {
                    VStack {
                        Text(Image(systemName: "checkmark.circle.fill")).foregroundStyle(.green).bold() + Text(" Authorized").bold()
                        ForEach(servers, id: \.clientIdentifier) { server in
                            Button {
                                HapticManager.shared.fireHaptic(.buttonPress)
                                musicSearchService.plexServerID = server.clientIdentifier
                            } label: {
                                Text(server.name)
                                    .frame(maxWidth: .infinity)
                                    .bold()
                            }
                            .buttonStyle(.bordered)
                            .tint(.accent)
//                            VStack(alignment: .leading) {
//                                ForEach(server.externalURIs, id: \.self) { connection in
//                                    Text(connection)
//                                }
//                            }
                        }
                        Text("Select Plex Server")
                            .foregroundStyle(.secondary)
                            .task {
                                isLoading = true
                                servers = await musicSearchService.getPlexServers()
                                isLoading = false
                            }

                        Button {
                            HapticManager.shared.fireHaptic(.buttonPress)
                            musicSearchService.plexServerID = nil
                            PlexAuthenticator.shared.authenticate()
                        } label: {
                            VStack {
                                Text("Reauthorize Plex")
                                    .frame(maxWidth: .infinity)
                                Text("Please use the Plex account on your existing Sonos and have remote access enabled.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.accent)
                    }
                    .fontDesign(.rounded)
                    .overlay {
                        ProgressView()
                            .opacity(isLoading ? 1 : 0)
                    }
                }
            }
            .listRowSeparator(.hidden)
            .navigationTitle("Plex")
            .navigationBarTitleDisplayMode(.inline)
            .addDismiss(action: dismiss.callAsFunction)
        }
    }
}
