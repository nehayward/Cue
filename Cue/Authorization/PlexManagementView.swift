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
            content
                // No title over the sign-in prompt, which names Plex itself.
                .navigationTitle(isSignedIn ? "Plex" : "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Dismiss", systemImage: "xmark") { dismiss() }
                    }

                    // The Subsonic and Audiobookshelf sheets' title, Connected
                    // under it.
                    if isSignedIn {
                        ToolbarItem(placement: .principal) {
                            VStack {
                                Text("Plex")
                                if musicSearchService.isPlexAuthorized {
                                    Text("Connected")
                                        .font(.caption.smallCaps())
                                        .foregroundStyle(.green.gradient)
                                }
                            }
                        }
                    }
                }
                // Signing in turns Plex on, as the Subsonic and Audiobookshelf
                // sheets do: onboarding switches off what wasn't chosen, and a
                // Plex signed in from the Audiobooks tab afterwards showed no
                // books.
                .onChange(of: plexAuthenticator.authToken) { old, new in
                    if old == nil, new != nil {
                        CoreFeatures.shared.enabledServices(.plex).wrappedValue = true
                    }
                }
        }
    }

    private var isSignedIn: Bool {
        plexAuthenticator.authToken != nil
    }

    @ViewBuilder
    private var content: some View {
        if !isSignedIn {
            signInPrompt
        } else {
            settingsList
        }
    }

    private var settingsList: some View {
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

            if musicSearchService.plexServerID != nil {
                PlexAudiobookSettingsSection(serverID: musicSearchService.plexServerID)
            }
        }
    }

    /// Shown until the account is linked. Without it the sheet went straight
    /// to the server picker and reported "No Plex servers found" to someone
    /// who simply hadn't signed in yet. The monitor polls for the PIN the
    /// browser sign-in approves, so it runs only while this prompt is up.
    /// In the type of Browse's set-up prompts, a column of its own centred a
    /// little above the middle of the sheet, its button held to the column
    /// rather than run across an iPad's sheet, and how the sign-in works as
    /// small print under it.
    private var signInPrompt: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    ServiceMarkTile(service: .plex, size: 72)
                        .padding(.bottom, 12)
                    Text("Connect to Plex")
                        .font(.title2.bold())
                    Text(signInMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        plexAuthenticator.authenticate()
                    } label: {
                        Text(plexAuthenticator.isStartingSignIn ? "Opening Plex…" : "Sign In to Plex")
                            .font(.headline)
                            .frame(maxWidth: 260)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(plexAuthenticator.isStartingSignIn)

                    if let error = plexAuthenticator.signInError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else {
                        // Kept whole across the line break.
                        Text("Plex opens in Safari, so your saved password and Sign\u{00A0}in\u{00A0}with\u{00A0}Apple or Google work.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 12) {
                    // The same sign-in in the browser app, for a password
                    // manager that doesn't fill in the sheet. The poll picks
                    // up the approval when Cue comes back.
                    if let url = plexAuthenticator.authorizationURL {
                        Link(destination: url) {
                            Label("Open in Browser Instead", systemImage: "safari")
                        }
                    }

                    Link(destination: URL(string: "https://support.plex.tv/articles/200289506-remote-access/")!) {
                        HStack(spacing: 3) {
                            Text("About Remote Access")
                            Image(systemName: "arrow.up.forward")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                }
                .font(.footnote.weight(.medium))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.bottom, 72)
            .fontDesign(.rounded)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center, for: .alignment)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            plexAuthenticator.restartMonitor()
        }
        .onDisappear {
            plexAuthenticator.stopMonitor()
        }
    }

    /// Sonos plays Plex through its own Plex service, so with Sonos on the
    /// account has to be the one the system is linked to.
    private var signInMessage: String {
        guard SonosService.shared.isEnabled else {
            return "Play the music and audiobooks on your Plex server."
        }
        return "Play the music and audiobooks on your Plex server, here and on your Sonos speakers. Sign in with the Plex account your Sonos system uses."
    }
}

#Preview {
    PlexManagementView()
}
