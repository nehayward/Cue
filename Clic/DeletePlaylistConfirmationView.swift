import SwiftUI
import SonosKit

/// A compact confirmation presented before deleting a playlist. Playlist deletion is destructive
/// (and irreversible for Plex/Sonos), so we always confirm first.
struct DeletePlaylistConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AlertService.self) private var alertService

    let content: PlayableContent

    @State private var isDeleting = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash")
                .font(.largeTitle)
                .foregroundStyle(.red)
                .padding(.top, 8)

            Text("Delete Playlist?")
                .font(.title2)
                .fontWeight(.bold)
                .fontDesign(.rounded)

            Text("“\(content.title)” will be deleted. This can’t be undone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button(role: .destructive) {
                    delete()
                } label: {
                    Group {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("Delete Playlist")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isDeleting)

                Button("Cancel") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .disabled(isDeleting)
            }
            .fontWeight(.semibold)
            .padding(.top, 4)
        }
        .padding(24)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }

    private func delete() {
        isDeleting = true
        Task {
            let success: Bool
            switch content.content.service {
            case .spotify:
                success = await MusicSearchService.shared.deleteSpotifyPlaylist(playlistID: content.content.id)
            case .plex:
                success = await MusicSearchService.shared.deletePlexPlaylist(playlistID: content.content.id)
            case .library:
                await SonosService.shared.delete(playlistID: content.id)
                success = true
            default:
                success = false
            }

            await MainActor.run {
                if success {
                    alertService.showAlert(with: "Removed \(content.title)", imageName: "trash")
                } else {
                    alertService.showAlert(with: "Couldn’t remove \(content.title)", imageName: "exclamationmark.triangle")
                }
                isDeleting = false
                dismiss()
            }
        }
    }
}
