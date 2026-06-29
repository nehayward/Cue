import SwiftUI
import SonosKit

/// A compact confirmation presented before deleting a playlist. Playlist deletion is destructive
/// (and irreversible for Plex/Sonos), so we always confirm first. Dismiss with the toolbar ✕.
struct DeletePlaylistConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AlertService.self) private var alertService

    let content: PlayableContent

    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "trash")
                    .font(.largeTitle)
                    .foregroundStyle(.red)

                Text("Delete Playlist?")
                    .font(.title2)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)

                Text("“\(content.title)” will be deleted. This can’t be undone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(role: .destructive) {
                    delete()
                } label: {
                    if isDeleting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Delete Playlist")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(isDeleting)
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                    .disabled(isDeleting)
                }
            }
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
    }

    private func delete() {
        isDeleting = true
        Task {
            let success: Bool
            switch content.content.service {
            case .library:
                await SonosService.shared.delete(playlistID: content.id)
                success = true
            default:
                success = await MusicSearchService.shared.deleteServicePlaylist(content)
            }

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
