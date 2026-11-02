import SwiftUI
import SonosKit
import MusicSearchKit
import NukeUI
import Defaults

/// A share-sheet–style sheet for adding a track to playlists on its own service (Apple Music,
/// Spotify, Plex, Subsonic, Files). Supports selecting several playlists at once and adding them
/// all on Done. No Sonos library playlists: they play only on a speaker, and a playlist in Cue
/// has to play on this device too (CLAUDE.md, Product Priorities).
struct AddToPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AlertService.self) private var alertService

    let content: PlayableContent

    private let musicService = MusicSearchService.shared

    @State private var servicePlaylists: [PlayableContent] = []
    @State private var selected: [String: PlayableContent] = [:]
    @State private var query: String = ""
    @State private var isLoadingService = true
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName: String = ""
    @State private var recentKeys: [String] = []
    // iPad has room for the full-height sheet; iPhone opens at medium. Both stay resizable.
    @State private var detent: PresentationDetent = UIDevice.current.userInterfaceIdiom == .pad ? .large : .medium
    // PlayableContentRowView embeds PlayableMenuView, which needs a SelectedGroupService that the
    // sheet's environment doesn't provide. Supply a throwaway one (the header is non-interactive).
    @State private var headerGroupService = SelectedGroupService(group: nil)

    private var service: MusicService { content.content.service }

    /// Whether the item's own service has playlists it can go in. Tracks are always fine;
    /// Spotify also accepts albums (expanded into their tracks on add).
    static func hasServicePlaylists(for content: PlayableContent) -> Bool {
        let service = content.content.service
        guard [.apple, .spotify, .plex, .deezer, .subsonic, .files].contains(service) else { return false }
        if [.track, .libraryTrack].contains(content.content.type) { return true }
        return service == .spotify && [.album, .libraryAlbum].contains(content.content.type)
    }

    /// Whether the sheet has anything to offer. Menus check this before
    /// offering "Add to Playlist…", so it never opens on an empty list.
    static func canAdd(_ content: PlayableContent) -> Bool {
        hasServicePlaylists(for: content)
    }

    /// The playlists to display, split into the "Recently Added" quick-pick (top 3, hidden while
    /// searching) and everything else. Computed once per render — `playlistList` reads it in several
    /// places, so folding it into one value avoids rebuilding the lookup dictionary each time.
    private var displayedSections: (recent: [PlayableContent], other: [PlayableContent]) {
        let list = servicePlaylists
        guard query.isEmpty else {
            return ([], list.filter { $0.title.localizedCaseInsensitiveContains(query) })
        }
        // Match on the service-namespaced key so a recent id from one service can't surface a
        // same-id playlist of another.
        let byKey = Dictionary(list.map { (key(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let recent = recentKeys.compactMap { byKey[$0] }.prefix(3).map { $0 }
        let recentIDs = Set(recent.map(\.id))
        return (recent, list.filter { !recentIDs.contains($0.id) })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlayableContentRowView(item: content, hideContentType: true)
                    .environment(headerGroupService)
                    .allowsHitTesting(false)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                playlistList
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        addSelectedAndDismiss()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .labelStyle(.iconOnly)
                    .tint(.green.opacity(0.8))
                    .disabled(selected.isEmpty)
                    .accessibilityLabel("Done")
                }
            }
            .searchable(text: $query, prompt: "Find playlist")
            .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
                TextField("Playlist name", text: $newPlaylistName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { createPlaylist() }
            } message: {
                Text("Create a new \(service.title) playlist with “\(content.title)”.")
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .task {
            recentKeys = LastPlaylist.recentKeys
            servicePlaylists = await musicService.userPlaylists(for: service)
            isLoadingService = false
        }
    }

    // MARK: - Subviews

    /// Square artwork with a placeholder, used by the playlist rows.
    @ViewBuilder
    private func artwork(_ url: URL?, size: CGFloat, cornerRadius: CGFloat) -> some View {
        LazyImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var playlistList: some View {
        let sections = displayedSections
        return List {
            Button {
                newPlaylistName = content.metadata?.album ?? content.title
                showNewPlaylistAlert = true
            } label: {
                Label("New Playlist", systemImage: "plus")
                    .fontWeight(.semibold)
            }

            if isLoadingService {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            } else if sections.recent.isEmpty && sections.other.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list")
                    .listRowSeparator(.hidden)
            } else {
                if !sections.recent.isEmpty {
                    Section("Recently Added") {
                        ForEach(sections.recent) { selectableRow($0) }
                    }
                }
                Section {
                    ForEach(sections.other) { selectableRow($0) }
                } header: {
                    if !sections.recent.isEmpty { Text("All Playlists") }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func selectableRow(_ playlist: PlayableContent) -> some View {
        Button {
            toggle(playlist)
        } label: {
            row(for: playlist)
        }
        .tint(.primary)
    }

    /// Selection key namespaced by service, so two services' playlists that happen to share a
    /// raw id (e.g. both numeric) can't collide in the recent picks.
    private func key(for playlist: PlayableContent) -> String {
        "\(playlist.content.service.sonosRawValue):\(playlist.id)"
    }

    @ViewBuilder
    private func row(for playlist: PlayableContent) -> some View {
        let isSelected = selected[key(for: playlist)] != nil
        HStack(spacing: 12) {
            artwork(playlist.thumbnail ?? playlist.artwork, size: 44, cornerRadius: 6)

            Text(playlist.title)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .imageScale(.large)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .contentShape(.rect)
    }

    // MARK: - Actions

    private func toggle(_ playlist: PlayableContent) {
        let key = key(for: playlist)
        if selected[key] != nil {
            selected[key] = nil
        } else {
            selected[key] = playlist
        }
    }

    private func addSelectedAndDismiss() {
        let targets = Array(selected.values)
        guard !targets.isEmpty else { dismiss(); return }
        Task {
            var added: [PlayableContent] = []
            for playlist in targets {
                if await add(content, to: playlist) { added.append(playlist) }
            }
            if added.isEmpty {
                alertService.showAlert(with: "Couldn’t add to playlist", imageName: "exclamationmark.triangle")
            } else {
                let subtitle: LocalizedStringKey = added.count == 1
                    ? "Added to \(added[0].title)"
                    : "Added to \(added.count) playlists"
                alertService.showAlertContent(with: content, subtitle: subtitle, symbolName: "plus")
                if let last = added.last {
                    LastPlaylist.save(last)
                    deepLink(to: last)  // deepLink must run after showAlertContent creates the alert
                }
            }
            dismiss()
        }
    }

    /// Makes the resulting toast tap through to the playlist's detail screen.
    private func deepLink(to playlist: PlayableContent) {
        alertService.alert.handleTap = {
            MediaDetailPresenter.present(playlist)
        }
    }

    /// Adds `track` to `playlist`; returns whether it succeeded.
    private func add(_ track: PlayableContent, to playlist: PlayableContent) async -> Bool {
        await musicService.addToServicePlaylist(track: track, playlist: playlist)
    }

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            let created = await musicService.createServicePlaylist(name: name, seededWith: content, for: service)
            if let created {
                LastPlaylist.save(created)
                alertService.showAlertContent(with: content, subtitle: "Created \(created.title)", symbolName: "plus")
                deepLink(to: created)
            }
            dismiss()
        }
    }
}
