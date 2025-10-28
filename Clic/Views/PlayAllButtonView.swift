import CloudStorage
import MusicSearchKit
import Defaults
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults

struct PlayAllButtonView: View {
    @Environment(Router.self) private var router: Router?
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService?

    let item: PlayableContent?

    var body: some View {
        if let item {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                Task {
                    await play(position: item.content.type == .playlist ? .replace : .now)
                }
            } label: {
                Label("Play All", systemImage: "play.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.background)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .fontDesign(.rounded)
            .listRowSeparator(.hidden, edges: .all)
            .listRowBackground(Color.clear)
            .animation(.snappy, value: selectedGroupService?.group?.coordinatorRoom.track.trackID)
            .tint(.primary)
        } else {
            EmptyView()
        }
    }
    
    @MainActor
    private func play(position: QueuePosition = .now) async {
        if let item {
            let queueSong: ((GroupRoom) async throws -> Void) = { group in
                QueueManager.shared.addToQueue(item: QueueItem(playableContent: item, group: group, position: position, title: position.title))
            }
            
            guard let group = selectedGroupService?.group else {
                if let selectedGroupService {
                    router?.sheet(to: .selectGroup(selectedGroupService: selectedGroupService, onSelection: queueSong, content: item))
                }
                return
            }
            
            try? await queueSong(group)
        }
    }
}

#Preview {
    List {
        Text("Here")
        PlayAllButtonView(item: nil)
        PlayAllButtonView(item: .soundCloudLikes)
        PlayAllButtonView(item: .spotifyLikes)
    }
    .withEnvironments()
}
