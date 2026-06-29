import SwiftUI
import SonosKit
import MusicSearchKit
import NukeUI
import Defaults

/// A share-sheet–style sheet for adding a track to playlists. Segments between the track's own
/// streaming service (Apple Music / Spotify / Plex) and Sonos library playlists, remembering the
/// last-used segment. Supports selecting several playlists at once and adding them all on Done.
struct AddToPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(AlertService.self) private var alertService

    let content: PlayableContent

    private let musicService = MusicSearchService.shared

    @AppStorage(AppStorageKeys.addToPlaylistSegment) private var storedSegment: String = ""

    @State private var segment: Segment = .service
    @State private var servicePlaylists: [PlayableContent] = []
    @State private var sonosPlaylists: [PlayableContent] = []
    @State private var selected: [String: PlayableContent] = [:]
    @State private var query: String = ""
    @State private var isLoadingService = true
    @State private var isLoadingSonos = true
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName: String = ""
    @State private var recentKeys: [String] = []
    // PlayableContentRowView embeds PlayableMenuView, which needs a SelectedGroupService that the
    // sheet's environment doesn't provide. Supply a throwaway one (the header is non-interactive).
    @State private var headerGroupService = SelectedGroupService(group: nil)

    enum Segment: String { case service, sonos }

    private var service: MusicService { content.content.service }

    /// Whether the track's own service can take this item into one of its playlists. Tracks are
    /// always fine; Spotify also accepts albums (expanded into their tracks on add).
    private var hasServiceSegment: Bool {
        guard [.apple, .spotify, .plex, .deezer].contains(service) else { return false }
        if [.track, .libraryTrack].contains(content.content.type) { return true }
        return service == .spotify && [.album, .libraryAlbum].contains(content.content.type)
    }

    private var currentPlaylists: [PlayableContent] {
        let list = segment == .service ? servicePlaylists : sonosPlaylists
        guard !query.isEmpty else { return list }
        return list.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    /// Up to three recently-added playlists for the current segment, shown as a quick-pick.
    /// Hidden while searching.
    private var recentPlaylists: [PlayableContent] {
        guard query.isEmpty else { return [] }
        let list = segment == .service ? servicePlaylists : sonosPlaylists
        // Match on the service-namespaced key so a recent id from one service can't surface a
        // same-id playlist in the other segment.
        let byKey = Dictionary(list.map { (key(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        return recentKeys.compactMap { byKey[$0] }.prefix(3).map { $0 }
    }

    /// The full list minus anything already surfaced in "Recently Added".
    private var otherPlaylists: [PlayableContent] {
        let recent = Set(recentPlaylists.map(\.id))
        return currentPlaylists.filter { !recent.contains($0.id) }
    }

    private var isLoading: Bool {
        segment == .service ? isLoadingService : isLoadingSonos
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlayableContentRowView(item: content, hideContentType: true)
                    .environment(headerGroupService)
                    .environment(PlexRatingCache.shared)
                    .allowsHitTesting(false)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                if hasServiceSegment {
                    Picker("Destination", selection: $segment) {
                        Text(service.title).tag(Segment.service)
                        Text("Sonos").tag(Segment.sonos)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
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
                Text("Create a new \(segment == .service ? service.title : "Sonos") playlist with “\(content.title)”.")
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            recentKeys = LastPlaylist.recentKeys
            if hasServiceSegment, let saved = Segment(rawValue: storedSegment) {
                segment = saved
            } else {
                segment = hasServiceSegment ? .service : .sonos
            }
            await loadPlaylists()
        }
        // onChange (not task(id:)) so persistence only fires on a real change — task(id:) also runs
        // on first appearance and would clobber the saved segment before the load restores it.
        .onChange(of: segment) { _, newValue in
            storedSegment = newValue.rawValue
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

    @ViewBuilder
    private var playlistList: some View {
        List {
            Button {
                newPlaylistName = content.metadata?.album ?? content.title
                showNewPlaylistAlert = true
            } label: {
                Label("New Playlist", systemImage: "plus")
                    .fontWeight(.semibold)
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            } else if currentPlaylists.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list")
                    .listRowSeparator(.hidden)
            } else {
                if !recentPlaylists.isEmpty {
                    Section("Recently Added") {
                        ForEach(recentPlaylists) { selectableRow($0) }
                    }
                }
                Section {
                    ForEach(otherPlaylists) { selectableRow($0) }
                } header: {
                    if !recentPlaylists.isEmpty { Text("All Playlists") }
                }
            }
        }
        .listStyle(.plain)
        .animation(.default, value: segment)
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

    /// Selection key namespaced by service, so a Sonos playlist and a streaming playlist that
    /// happen to share a raw id (e.g. both numeric) can't collide across segments.
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

    private func loadPlaylists() async {
        async let sonos = sonosService.sonosPlaylists()
        if hasServiceSegment {
            servicePlaylists = await musicService.userPlaylists(for: service)
        }
        isLoadingService = false
        sonosPlaylists = await sonos
        isLoadingSonos = false
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
                if let last = added.last { LastPlaylist.save(last) }
                let subtitle: LocalizedStringKey = added.count == 1
                    ? "Added to \(added[0].title)"
                    : "Added to \(added.count) playlists"
                alertService.showAlertContent(with: content, subtitle: subtitle, symbolName: "plus")
                if let target = added.last { deepLink(to: target) }
            }
            dismiss()
        }
    }

    /// Makes the resulting toast tap through to the playlist's detail screen.
    private func deepLink(to playlist: PlayableContent) {
        alertService.alert.handleTap = {
            Router.main.presentedSheet = .mediaDetail(content: playlist, group: nil)
        }
    }

    /// Adds `track` to `playlist`; returns whether it succeeded.
    private func add(_ track: PlayableContent, to playlist: PlayableContent) async -> Bool {
        if playlist.content.service == .library {
            await sonosService.addToPlaylist(playlistID: playlist.id, playableContent: track)
            return true
        } else {
            return await musicService.addToServicePlaylist(track: track, playlist: playlist)
        }
    }

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            let created: PlayableContent?
            if segment == .service {
                created = await musicService.createServicePlaylist(name: name, seededWith: content, for: service)
            } else {
                await sonosService.createPlaylist(title: name)
                let playlists = await sonosService.sonosPlaylists()
                let match = playlists.first(where: { $0.title == name })
                if let match { await sonosService.addToPlaylist(playlistID: match.id, playableContent: content) }
                created = match
            }

            if let created {
                LastPlaylist.save(created)
                alertService.showAlertContent(with: content, subtitle: "Created \(created.title)", symbolName: "plus")
                deepLink(to: created)
            }
            dismiss()
        }
    }
}
