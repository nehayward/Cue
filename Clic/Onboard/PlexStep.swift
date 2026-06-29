import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI

/// Onboarding's Plex setup page — only shown when Plex was found among the
/// user's authorized Sonos services on the `ServicesStep`. Walks the user
/// through signing into Plex, then auto-picks sensible defaults (Remote Access
/// connection + the first music library) so the service is ready to use without
/// forcing a trip into Preferences. The picked library is still editable from
/// the list, and the connection type can be toggled before continuing.
struct PlexStep: View {
    var musicSearchService = MusicSearchService.shared
    var advance: () -> Void

    @State private var plexAuthenticator = PlexAuthenticator.shared
    @State private var servers: [PlexServer] = []
    /// Music libraries keyed by server `clientIdentifier`.
    @State private var librariesByServer: [String: [PlexLibrarySection]] = [:]
    /// A few artist artwork URLs per library (keyed by `PlexLibrarySection.id`),
    /// shown as overlapping circles to make libraries easier to recognize.
    @State private var artworkByLibrary: [String: [URL]] = [:]
    @State private var isLoading = false

    private var isAuthorized: Bool { plexAuthenticator.authToken != nil }

    /// Header copy reflects the current state so it never contradicts the body
    /// (e.g. claiming "we picked a library" while still loading or when none
    /// were found).
    private var headerSubtitle: String {
        if !isAuthorized {
            return "Sign in to your Plex account — the same one linked to your Sonos system."
        }
        if isLoading {
            return "Getting your Plex libraries ready…"
        }
        if allLibraries.isEmpty {
            return "Signed in to Plex, but we couldn't find a music library yet."
        }
        return "We picked your first library and Remote Access. Tap a library to change it."
    }

    /// All (server, library) pairs flattened for the picker list, preserving
    /// server order then library order.
    private var allLibraries: [(server: PlexServer, library: PlexLibrarySection)] {
        servers.flatMap { server -> [(PlexServer, PlexLibrarySection)] in
            guard let id = server.clientIdentifier else { return [] }
            return (librariesByServer[id] ?? []).map { (server, $0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isAuthorized {
                authorizedContent
            } else {
                authPrompt
            }

            Spacer(minLength: 0)

            footer
        }
        .multilineTextAlignment(.center)
        .onAppear { plexAuthenticator.restartMonitor() }
        .onDisappear { plexAuthenticator.stopMonitor() }
        // Auth completes asynchronously via the polling monitor — when the
        // token lands, load servers and apply the default selection.
        .onChange(of: plexAuthenticator.authToken, initial: true) { _, token in
            if token != nil { Task { await loadAndSelectDefaults() } }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            MediaSearchService.plex.iconForMusicService
                .frame(width: 44, height: 44)
                .padding(.bottom, 4)

            Text("Set Up Plex")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(headerSubtitle)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 28)
        }
        .padding(.top, 36)
        .padding(.bottom, 24)
    }

    // MARK: - Not authorized

    private var authPrompt: some View {
        VStack(spacing: 14) {
            Link(destination: URL(string: "https://support.plex.tv/articles/200289506-remote-access/")!) {
                HStack(spacing: 4) {
                    Text("Remote Access Setup")
                    Image(systemName: "arrow.up.forward")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)

            if let url = plexAuthenticator.authorizationURL {
                Link(destination: url) {
                    Text(url.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .textSelection(.enabled)
                .padding(.horizontal, 28)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Authorized

    @ViewBuilder
    private var authorizedContent: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Loading your Plex libraries…")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else if allLibraries.isEmpty {
            VStack(spacing: 8) {
                Text("No music libraries found")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Make sure your Plex Media Server is online with Remote Access enabled, then continue.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 28)
            }
            .padding(.top, 16)
        } else {
            libraryList
        }
    }

    private var libraryList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(allLibraries, id: \.library.id) { pair in
                    libraryRow(server: pair.server, library: pair.library)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }

    private func libraryRow(server: PlexServer, library: PlexLibrarySection) -> some View {
        let isSelected = musicSearchService.plexServerID == server.clientIdentifier
            && musicSearchService.plexLibrarySelectionID == library.key

        return Button {
            HapticManager.shared.fireHaptic(.selection)
            musicSearchService.plexServerID = server.clientIdentifier
            musicSearchService.plexLibrarySelectionID = library.key
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(library.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text([server.name, server.device].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let urls = artworkByLibrary[library.id], !urls.isEmpty {
                    ArtistCircleCluster(urls: urls)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.08 : 0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(isSelected ? 0.14 : 0.06), lineWidth: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3), value: isSelected)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            if isAuthorized {
                PrimaryPillButton(title: "Continue", action: advance)
            } else {
                PrimaryPillButton(title: "Authorize Plex", icon: "arrow.up.forward.app") {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    plexAuthenticator.authenticate()
                }
                Button(action: advance) {
                    Text("Skip for Now")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    // MARK: - Loading & default selection

    /// Fetches servers and their music libraries, then — for a fresh setup
    /// (no server picked yet) — defaults the connection to Remote Access and
    /// selects the first available library so Plex works out of the box.
    @MainActor
    private func loadAndSelectDefaults() async {
        isLoading = true
        defer { isLoading = false }

        let freshSetup = musicSearchService.plexServerID == nil
        // Default to Remote Access — works from anywhere and matches the
        // recommendation in the full setup flow. Set before fetching libraries
        // so the section URLs resolve against the remote connection.
        if freshSetup {
            musicSearchService.plexConnectionPreference = .nonLocal
        }

        let fetchedServers = await musicSearchService.getPlexServers()
        servers = fetchedServers
        librariesByServer = [:]
        artworkByLibrary = [:]

        await withTaskGroup(of: Void.self) { group in
            for server in fetchedServers {
                guard let id = server.clientIdentifier else { continue }
                group.addTask {
                    let sections = await PlexAPI.shared.getMusicLibraries(server: server)
                    await MainActor.run { librariesByServer[id] = sections }
                }
            }
        }

        // Auto-pick the first server that actually has a music library, and
        // its first library — only when the user hasn't chosen one already.
        if freshSetup,
           let server = fetchedServers.first(where: { ($0.clientIdentifier.flatMap { librariesByServer[$0] })?.isEmpty == false }),
           let id = server.clientIdentifier,
           let firstLibrary = librariesByServer[id]?.first {
            musicSearchService.plexServerID = id
            musicSearchService.plexLibrarySelectionID = firstLibrary.key
        }

        // Fetch artwork previews in the background so the library list shows
        // immediately and the circles fill in as they arrive.
        Task { await loadArtwork() }
    }

    /// Loads a few artist artwork URLs for each library to render the preview
    /// circles. Runs after the list is visible and updates rows incrementally.
    @MainActor
    private func loadArtwork() async {
        await withTaskGroup(of: Void.self) { group in
            for pair in allLibraries {
                let library = pair.library
                guard artworkByLibrary[library.id] == nil else { continue }
                let server = pair.server
                group.addTask {
                    let artists = await PlexAPI.shared.getArtists(server: server, sectionKey: library.key)
                    let urls = Array(artists.compactMap(\.thumbImageURL).prefix(3))
                    await MainActor.run { artworkByLibrary[library.id] = urls }
                }
            }
        }
    }
}

/// A small cluster of overlapping circular artist thumbnails, used as a trailing
/// accessory on a Plex library row so libraries are easier to recognize at a
/// glance. Each circle gets a solid white ring so overlapping circles read as
/// cleanly separated.
private struct ArtistCircleCluster: View {
    let urls: [URL]
    var diameter: CGFloat = 38
    var overlap: CGFloat = 14
    var ringWidth: CGFloat = 2

    private var shown: [URL] { Array(urls.prefix(3)) }

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, url in
                avatar(url)
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
                    // White ring separates each circle from the one behind it.
                    // Front circles sit on top so their ring forms the seam.
                    .overlay { Circle().strokeBorder(Color.white, lineWidth: ringWidth) }
                    .zIndex(Double(shown.count - index))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func avatar(_ url: URL) -> some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                Circle()
                    .fill(.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "music.mic")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }
            }
        }
    }
}
