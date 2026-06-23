import FocusOnAppear
import SwiftUI
import SonosKit

struct NewPlaylistView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(AlertService.self) var alertService: AlertService
    @Environment(\.dismiss) var dismiss

    var group: GroupRoom? = nil
    @State var playlist: PlayableContent? = nil
    @State var playlistName: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text(playlist != nil ? "Rename Playlist" : "New Playlist")
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
            } else {
                await sonosService.createPlaylist(title: playlistName)
                let playlists = await sonosService.sonosPlaylists()
                if let newPlaylist = playlists.first(where: { $0.title == playlistName }) {
                    alertService.showAlertContent(with: newPlaylist, subtitle: "Created Playlist", symbolName: "checkmark")
                    alertService.alert.handleTap = {
                        Router.main.presentedSheet = .mediaDetail(content: newPlaylist, group: nil)
                    }

                    // Save as last used playlist and rebuild menu
                    LastPlaylist.save(newPlaylist)
                }
            }
            dismiss()
        }
    }
}

#Preview {
    NewPlaylistView()
        .environment(SonosService.shared)
}
