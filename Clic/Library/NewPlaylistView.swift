import FocusOnAppear
import OrderedCollections
import SwiftUI
import SonosKit

struct NewPlaylistView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(AlertService.self) var alertService: AlertService
    @Environment(\.dismiss) var dismiss

    var group: GroupRoom? = nil
    /// Which service to create on. `.library` is a Sonos playlist; others create via the service API.
    var service: MusicService = .library
    @State var playlist: PlayableContent? = nil
    @State var playlistName: String = ""

    private var titleText: String {
        if playlist != nil { return "Rename Playlist" }
        return service == .library ? "New Playlist" : "New \(service.title) Playlist"
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel")
                Spacer()
            }

            Text(titleText)
                .font(.title3)
                .fontWeight(.bold)
                .fontDesign(.rounded)

            TextField("Playlist Title", text: $playlistName)
                .textFieldStyle(.roundedBorder)
                .focusOnAppear()
                .onSubmit(createOrUpdate)

            Button {
                createOrUpdate()
            } label: {
                Text(playlist != nil ? "Update" : "Create")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(playlistName.isEmpty || playlistName == playlist?.title)
        }
        .padding(20)
        .presentationDetents([.height(250)])
        .presentationBackground(.regularMaterial)
        .task {
            if let playlist {
                playlistName = playlist.title
            }
        }
    }

    private func createOrUpdate() {
        guard !playlistName.isEmpty else { return }
        Task {
            if let playlist {
                try? await sonosService.renamePlaylist(existingPlaylist: playlist, newName: playlistName)
            } else if let group {
                try? await sonosService.saveQueue(ip: group.ip, title: playlistName)
            } else if service == .library {
                await sonosService.createPlaylist(title: playlistName)
                let playlists = await sonosService.sonosPlaylists()
                if let newPlaylist = playlists.first(where: { $0.title == playlistName }) {
                    announceCreated(newPlaylist)
                }
            } else if let newPlaylist = await MusicSearchService.shared.createServicePlaylist(name: playlistName, for: service) {
                announceCreated(newPlaylist)
            } else {
                alertService.showAlert(with: "Couldn’t create playlist", imageName: "exclamationmark.triangle")
            }
            dismiss()
        }
    }

    /// Toast + deep-link to the freshly created playlist, and record it as the last-used one.
    private func announceCreated(_ playlist: PlayableContent) {
        insertIntoBrowseList(playlist)
        alertService.showAlertContent(with: playlist, subtitle: "Created Playlist", symbolName: "checkmark")
        alertService.alert.handleTap = {
            Router.main.presentedSheet = .mediaDetail(content: playlist, group: nil)
        }
        LastPlaylist.save(playlist)
    }

    /// Prepend the new playlist into the service's browse collection so the playlist list refreshes
    /// immediately (the grids/lists bind to these).
    private func insertIntoBrowseList(_ playlist: PlayableContent) {
        switch service {
        case .apple: AppleMusicBrowseService.shared.userPlaylists.insert(playlist, at: 0)
        case .spotify: SpotifyBrowseService.shared.playlists.insert(playlist, at: 0)
        case .deezer: DeezerBrowseService.shared.userPlaylists.insert(playlist, at: 0)
        case .plex: PlexBrowseService.shared.userPlaylists.insert(playlist, at: 0)
        case .library: LibraryBrowseService.shared.playlists.insert(playlist, at: 0)
        default: break
        }
    }
}

#Preview {
    NewPlaylistView()
        .environment(SonosService.shared)
}
