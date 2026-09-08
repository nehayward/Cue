import SwiftUI
import SonosKit

struct QueueMoreInfoView: View {
    var group: GroupRoom
    var router: Router
    
    @Binding var editMode: EditMode
    @Binding var queueMode: QueueMode
    @Binding var upNextTracks: [PlayableContent]
    
    @State private var clearQueueConfirmation: Bool = false

    var body: some View {
        Menu {
            Button {
                withAnimation {
                    editMode = editMode.isEditing ? .inactive : .active
                }
            } label: {
                Label(editMode.isEditing ? "Done" : "Edit",
                      systemImage: editMode.isEditing ? "checkmark" : "pencil")
            }

            Button {
                queueMode = queueMode == .full ? .upNext : .full
            } label: {
                Label(queueMode == .full ? "Up Next" : "Queue",
                      systemImage: queueMode == .full ? "text.line.first.and.arrowtriangle.forward" : "list.bullet")
            }

            Button {
                Task {
                    router.presentedSheet = .newPlaylist(group: group)
                }
            } label: {
                Label("Save Queue", systemImage: "square.and.arrow.down")
                Text("Create Sonos Playlist")
            }

            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                Router.main.presentedSheet = .search(group: group)
            } label: {
                Label("Search", systemImage: "magnifyingglass")
                    .fontDesign(.rounded)
            }
            Button(role: .destructive) {
                clearQueueConfirmation.toggle()
            } label: {
                Label("Clear Queue", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("Queue Options")
        .help("Queue Options")
        .confirmationDialog("Clear Queue", isPresented: $clearQueueConfirmation, titleVisibility: .hidden) {
            Button {
                upNextTracks.removeAll()
                group.coordinatorRoom.queue.removeAll()
        
                Task {
                    try await SonosService.shared.clearQueue(group.coordinatorRoom.ip)
                }
            } label: {
                Text("Clear Queue")
                    .bold()
            }
        }
    }
}
