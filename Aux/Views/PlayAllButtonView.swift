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
    @AppStorage(Defaults.AppStorageKeys.defaultPlayAction) private var replaceQueueByDefault: Bool = false
    
    let item: PlayableContent?
    
    var body: some View {
        if item != nil {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                Task {
                    await play()
                }
            } label: {
                Text("Play All")
                    .fontWeight(.semibold)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonBorderShape(.capsule)
            .fontDesign(.rounded)
            .listRowSeparator(.hidden, edges: .all)
            .listRowBackground(Color.clear)
            .contentShape(.rect)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .foregroundStyle(.ultraThickMaterial)
            }
        } else {
            EmptyView()
        }
    }
    
    @MainActor
    private func play(position: QueuePosition? = nil) async {
        if let item {
            let defaultPosition = position ?? QueuePosition.defaultPosition(
                for: item.content.type,
                replaceQueueByDefault: replaceQueueByDefault
            )
            let queueSong: ((GroupRoom, QueuePosition) async throws -> Void) = { [item] group, selectedPosition in
                QueueManager.shared.addToQueue(item: QueueItem(playableContent: item, group: group, position: selectedPosition, title: selectedPosition.title))
            }

            guard let group = selectedGroupService?.group else {
                await PlayDestinationRouter.play(item, position: defaultPosition, queue: queueSong)
                return
            }

            try? await queueSong(group, defaultPosition)
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
