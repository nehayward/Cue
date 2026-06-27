import FocusOnAppear
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
            Text(titleText)
                .font(.headline)
                .fontDesign(.rounded)

            TextField("Playlist Title", text: $playlistName)
                .textFieldStyle(.roundedBorder)
                .focusOnAppear()
                .onSubmit(createOrUpdate)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(playlist != nil ? "Update" : "Create") {
                    createOrUpdate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(playlistName.isEmpty || playlistName == playlist?.title)
            }
        }
        .padding(24)
        .presentationDetents([.height(160)])
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
        alertService.showAlertContent(with: playlist, subtitle: "Created Playlist", symbolName: "checkmark")
        alertService.alert.handleTap = {
            Router.main.presentedSheet = .mediaDetail(content: playlist, group: nil)
        }
        LastPlaylist.save(playlist)
    }
}

#Preview {
    NewPlaylistView()
        .environment(SonosService.shared)
}
