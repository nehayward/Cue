import Foundation
import SonosKit
import SwiftUI

extension View {
    @MainActor
    func dropDestinationPlay(on group: GroupRoom, position: QueuePosition = .now, isTargeted: @escaping (Bool) -> Void = { _ in }) -> some View {
        return dropDestination(for: MultiTypeTransferable.self) {
            items,
            location in
            print(items)
            guard let item = items.first else { return false }
            switch item {
            case let .playable(content):
                Task {
                    let position = [.playlist, .libraryPlaylist].contains(content.content.type) ? .replace : position

                    let queueItem = QueueItem(
                        playableContent: content,
                        group: group,
                        position: position,
                        title: position.title,
                        showBanner: true
                    )
                    QueueManager.shared.addToQueue(item: queueItem)
                }
                return true
            case let .url(url):
                Task {
                    guard let playableContent = await SonosService.shared.getContent(from: url) else {
                        return
                    }
                    let position = [.playlist, .libraryPlaylist].contains(playableContent.content.type) ? .replace : position

                    let queueItem = QueueItem(
                        playableContent: playableContent,
                        group: group,
                        position: position,
                        title: position.title,
                        showBanner: true
                    )
                    QueueManager.shared.addToQueue(item: queueItem)
                }
                return true
            }
        } isTargeted: { targeting in
            isTargeted(targeting)
        }
    }
}
