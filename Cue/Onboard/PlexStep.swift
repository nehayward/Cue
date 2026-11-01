import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI

/// Onboarding's Plex setup page — only shown when Plex was chosen on the
/// `ServicesStep` and isn't signed in with a library yet. Walks the user
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
    /// A first read of the servers has finished: until then the page shows
    /// it loading, not "No music libraries found" for the moment before the
    /// read starts.
    @State private var hasLoaded = false
    @State private var contentIn = false
    @State private var rowsIn = false

    private var isAuthorized: Bool { plexAuthenticator.authToken != nil }

    /// What the page shows below its header. Each comes in with a slide and
    /// a fade, as the steps do, rather than popping in when a read finishes.
    private enum Phase: Hashable {
        case signIn, loading, empty, libraries
    }

    private var phase: Phase {
        guard isAuthorized else { return .signIn }
        if isLoading || !hasLoaded { return .loading }
        return allLibraries.isEmpty ? .empty : .libraries
    }

    /// What leaves fades at once and what arrives slides up a beat later,
    /// so "Loading…" isn't still on top of the libraries coming in.
    private var phaseTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 28))
                .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.12)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }

    /// Header copy reflects the current state so it never contradicts the body
    /// (e.g. claiming "we picked a library" while still loading or when none
    /// were found).
    private var headerSubtitle: String {
        if !isAuthorized {
            return "Sign in to play your Plex server's music here and on your speakers. Plex opens in Safari, so a saved password fills in."
        }
        if phase == .loading {
            return "Getting your Plex libraries ready…"
        }
        if allLibraries.isEmpty {
            return "Signed in to Plex, but we couldn't find a music library yet."
        }
        return "We picked your first library. Tap a library to change it, or adjust how Cue connects."
    }

    private var connectionBinding: Binding<PlexAPI.ConnectionPreference> {
        Binding(
            get: { musicSearchService.plexConnectionPreference },
            set: { musicSearchService.plexConnectionPreference = $0 }
        )
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

            ZStack(alignment: .top) {
                switch phase {
                case .signIn:
                    authPrompt
                        .transition(phaseTransition)
                case .loading:
                    loadingContent
                        .transition(phaseTransition)
                case .empty:
                    emptyContent
                        .transition(phaseTransition)
                case .libraries:
                    librariesContent
                        .transition(phaseTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(contentIn ? 1 : 0)
            .offset(y: contentIn ? 0 : 24)
            .animation(.spring(response: 0.55, dampingFraction: 0.85), value: phase)

            footer
                .opacity(contentIn ? 1 : 0)
                .offset(y: contentIn ? 0 : 24)
                .animation(.easeInOut(duration: 0.25), value: isAuthorized)
        }
        .multilineTextAlignment(.center)
        .onAppear {
            plexAuthenticator.restartMonitor()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { contentIn = true }
        }
        .onDisappear { plexAuthenticator.stopMonitor() }
        // Auth completes asynchronously via the polling monitor — when the
        // token lands, load servers and apply the default selection.
        .onChange(of: plexAuthenticator.authToken, initial: true) { _, token in
            if token != nil { Task { await loadAndSelectDefaults() } }
        }
        // Reload libraries/artwork over the newly chosen connection when the
        // user switches connection type.
        .onChange(of: musicSearchService.plexConnectionPreference) { _, _ in
            if isAuthorized { Task { await loadAndSelectDefaults() } }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            // The services page's tile, larger.
            ServiceMarkTile(service: .plex, size: 60)
                .environment(\.colorScheme, .dark)
                .padding(.bottom, 4)

            Text("Set Up Plex")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(headerSubtitle)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 28)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: headerSubtitle)
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

            if let error = plexAuthenticator.signInError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 28)
            }

            // The same sign-in in the browser app, for a password manager
            // that doesn't fill in the sheet. The poll picks up the approval
            // when Cue comes back.
            if let url = plexAuthenticator.authorizationURL {
                Link(destination: url) {
                    Label("Open in Browser Instead", systemImage: "safari")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Authorized

    private var loadingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Loading your Plex libraries…")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var emptyContent: some View {
        VStack(spacing: 8) {
            Text("No music libraries found")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Make sure your Plex Media Server is online and reachable, then continue.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 28)
        }
        .padding(.top, 16)
    }

    private var librariesContent: some View {
        VStack(spacing: 16) {
            // Same connection switch used on the Plex settings screen.
            PlexConnectionPicker(selection: connectionBinding)
                .environment(\.colorScheme, .dark)
                .padding(.horizontal, 20)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity, alignment: .center)

            libraryList
        }
        // The rows follow the list in, one after another.
        .onAppear { rowsIn = true }
        .onDisappear { rowsIn = false }
    }

    private var libraryList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(allLibraries.enumerated()), id: \.element.library.id) { index, pair in
                    libraryRow(server: pair.server, library: pair.library)
                        .opacity(rowsIn ? 1 : 0)
                        .offset(y: rowsIn ? 0 : 18)
                        .animation(
                            .spring(response: 0.55, dampingFraction: 0.85).delay(0.12 + Double(index) * 0.06),
                            value: rowsIn
                        )
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
                PrimaryPillButton(
                    title: plexAuthenticator.isStartingSignIn ? "Opening Plex…" : "Sign In to Plex",
                    icon: "arrow.up.forward.app",
                    isDisabled: plexAuthenticator.isStartingSignIn
                ) {
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
        // Avoid overlapping loads (e.g. auth + connection-change firing close
        // together) racing the shared state.
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let freshSetup = musicSearchService.plexServerID == nil
        // No need to write a default connection preference: when unset it
        // already resolves to Automatic (fast local at home, remote away), and
        // not writing means we (a) respect a returning user's explicit choice
        // and (b) don't self-trigger the connection-preference observer below.

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
        hasLoaded = true

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
                    // Fetch a few more than the 3 shown so we still get 3 even
                    // when some artists have no artwork.
                    let artists = await PlexAPI.shared.getArtists(server: server, sectionKey: library.key, limit: 6)
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
