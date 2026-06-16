import SwiftUI
import UIKit
import SonosKit
import MusicSearchKit
import NukeUI
import Defaults

/// A share-sheet–style sheet for adding a track to playlists. Segments between the track's own
/// streaming service (Apple Music / Spotify / Plex) and Sonos library playlists, remembering the
/// last-used segment. Supports selecting several playlists at once and adding them all on Done.
struct AddToPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Environment(SonosService.self) private var sonosService
    @Environment(AlertService.self) private var alertService

    let content: PlayableContent

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

    enum Segment: String { case service, sonos }

    private var service: MusicService { content.content.service }

    /// The track's own service supports playlists *and* the item is a track (not an album).
    private var hasServiceSegment: Bool {
        [.apple, .spotify, .plex].contains(service) && [.track, .libraryTrack].contains(content.content.type)
    }

    private var currentPlaylists: [PlayableContent] {
        let list = segment == .service ? servicePlaylists : sonosPlaylists
        guard !query.isEmpty else { return list }
        return list.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var isLoading: Bool {
        segment == .service ? isLoadingService : isLoadingSonos
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                banner
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { addSelectedAndDismiss() }
                        .fontWeight(.semibold)
                        .disabled(selected.isEmpty)
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
            if hasServiceSegment, let saved = Segment(rawValue: storedSegment) {
                segment = saved
            } else {
                segment = hasServiceSegment ? .service : .sonos
            }
            await loadPlaylists()
        }
        .onChange(of: segment) { _, newValue in
            storedSegment = newValue.rawValue
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var banner: some View {
        HStack(spacing: 12) {
            LazyImage(url: content.artwork ?? content.thumbnail) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.headline)
                    .lineLimit(1)
                if !content.subtitle.isEmpty {
                    Text(content.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
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
                ForEach(currentPlaylists) { playlist in
                    Button {
                        toggle(playlist)
                    } label: {
                        row(for: playlist)
                    }
                    .tint(.primary)
                }
            }
        }
        .listStyle(.plain)
        .animation(.default, value: segment)
    }

    @ViewBuilder
    private func row(for playlist: PlayableContent) -> some View {
        let isSelected = selected[playlist.id] != nil
        HStack(spacing: 12) {
            LazyImage(url: playlist.thumbnail ?? playlist.artwork) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(playlist.title)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .imageScale(.large)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .contentShape(.rect)
    }

    // MARK: - Actions

    private func toggle(_ playlist: PlayableContent) {
        if selected[playlist.id] != nil {
            selected[playlist.id] = nil
        } else {
            selected[playlist.id] = playlist
        }
    }

    private func loadPlaylists() async {
        async let sonos = sonosService.sonosPlaylists()
        if hasServiceSegment {
            servicePlaylists = await fetchServicePlaylists()
        }
        isLoadingService = false
        sonosPlaylists = await sonos
        isLoadingSonos = false
    }

    private func fetchServicePlaylists() async -> [PlayableContent] {
        switch service {
        case .apple: return await MusicSearchService.shared.appleUserPlaylists()
        case .spotify: return await MusicSearchService.shared.spotifyEditablePlaylists()
        case .plex: return await MusicSearchService.shared.plexUserPlaylists()
        default: return []
        }
    }

    private func addSelectedAndDismiss() {
        let targets = Array(selected.values)
        guard !targets.isEmpty else { dismiss(); return }
        Task {
            for playlist in targets {
                await add(content, to: playlist)
            }
            await MainActor.run {
                persistLast(targets.last)
                let subtitle: LocalizedStringKey = targets.count == 1
                    ? "Added to \(targets[0].title)"
                    : "Added to \(targets.count) playlists"
                alertService.showAlertContent(with: content, subtitle: subtitle, symbolName: "plus")
                dismiss()
            }
        }
    }

    private func add(_ track: PlayableContent, to playlist: PlayableContent) async {
        if playlist.content.service == .library {
            await sonosService.addToPlaylist(playlistID: playlist.id, playableContent: track)
        } else {
            _ = await MusicSearchService.shared.addToServicePlaylist(track: track, playlist: playlist)
            PlaylistEditCoordinator.shared.registerExternalAdd(track: track, to: playlist, undoManager: undoManager)
        }
    }

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            let created: PlayableContent?
            if segment == .service {
                switch service {
                case .apple: created = await MusicSearchService.shared.createApplePlaylist(name: name, addingTrack: content)
                case .spotify: created = await MusicSearchService.shared.createSpotifyPlaylist(name: name, addingTrack: content)
                case .plex: created = await MusicSearchService.shared.createPlexPlaylist(name: name, track: content)
                default: created = nil
                }
            } else {
                await sonosService.createPlaylist(title: name)
                let playlists = await sonosService.sonosPlaylists()
                let match = playlists.first(where: { $0.title == name })
                if let match { await sonosService.addToPlaylist(playlistID: match.id, playableContent: content) }
                created = match
            }

            await MainActor.run {
                if let created {
                    persistLast(created)
                    alertService.showAlertContent(with: content, subtitle: "Created \(created.title)", symbolName: "plus")
                }
                dismiss()
            }
        }
    }

    private func persistLast(_ playlist: PlayableContent?) {
        guard let playlist else { return }
        UserDefaults.standard.set(playlist.id, forKey: AppStorageKeys.lastPlaylistID)
        UserDefaults.standard.set(playlist.title, forKey: AppStorageKeys.lastPlaylistTitle)
        UserDefaults.standard.set(playlist.content.service.sonosRawValue, forKey: AppStorageKeys.lastPlaylistService)
        #if targetEnvironment(macCatalyst)
        UIMenuSystem.main.setNeedsRebuild()
        #endif
    }
}
