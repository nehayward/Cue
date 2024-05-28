import Combine
import SwiftUI
import SonosKit

struct NewPlaylistView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(\.dismiss) var dismiss

    var group: GroupRoom? = nil
    @State var playlist: PlayableContent? = nil
    @State var playlistName: String = ""
    @FocusState private var isPlaylistNameFocused: Bool

    var body: some View {
        Form {
            TextField("Name", text: $playlistName)
                .focused($isPlaylistNameFocused)
            if let playlist {
                Button {
                    Task {
                        try? await sonosService.renamePlaylist(existingPlaylist: playlist, newName: playlistName)
                        dismiss()
                    }
                } label: {
                    Text("Update")
                        .frame(maxWidth: .infinity)
                        .bold()
                        .fontDesign(.rounded)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
                .padding(.vertical)
                .disabled(playlistName == playlist.title)
            } else {
                Button {
                    Task {
                        if let group {
                            try? await sonosService.saveQueue(ip: group.ip, title: playlistName)
                        } else {
                            await sonosService.createPlaylist(title: playlistName)
                        }
                        dismiss()
                    }
                } label: {
                    Text("Create")
                        .frame(maxWidth: .infinity)
                        .bold()
                        .fontDesign(.rounded)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
                .padding(.vertical)
                .disabled(playlistName.isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .presentationDetents([.fraction(0.3)])
        .presentationBackground(.thinMaterial)
        .task {
            isPlaylistNameFocused = true
            if let playlist {
                playlistName = playlist.title
            }
        }
        .addDismiss(action: dismiss.callAsFunction)
    }
}

#Preview {
    NewPlaylistView()
        .environment(SonosService.shared)
}
