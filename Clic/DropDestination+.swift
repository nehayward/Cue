import Foundation
import SonosKit
import SwiftUI

extension View {
    @MainActor
    func dropDestinationPlay(on group: GroupRoom, position: QueuePosition = .now, isTargeted: @escaping (Bool) -> Void = { _ in }) -> some View {
        return dropDestination(for: URL.self) { items, location in
            guard let item = items.first else { return false }
            Task {
                guard let playableContent = await SonosService.shared.getContent(from: item) else {
                    return
                }
                QueueManager.shared.addToQueue(item: QueueItem(playableContent: playableContent, group: group, position: position, title: position.title, showBanner: true))
            }
            return true
        } isTargeted: { targeting in
            isTargeted(targeting)
        }
        .dropDestination(for: PlayableContent.self) { items, location in
            guard let item = items.first else { return false }
            Task {
                QueueManager.shared.addToQueue(item: QueueItem(playableContent: item, group: group, position: position, title: position.title, showBanner: true))
            }
            return true
        } isTargeted: { targeting in
            isTargeted(targeting)
        }
    }
}
