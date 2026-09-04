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

    /// The local player's twin of `dropDestinationPlay(on:)`: what lands
    /// goes into this device's queue. Containers are expanded the way the
    /// play sheet expands them, and anything the device can't play is
    /// reported rather than dropped on the floor.
    @MainActor
    func dropDestinationPlayOnDevice(position: QueuePosition = .now, isTargeted: @escaping (Bool) -> Void = { _ in }) -> some View {
        return dropDestination(for: MultiTypeTransferable.self) { items, _ in
            guard let item = items.first else { return false }
            Task { @MainActor in
                let content: PlayableContent?
                switch item {
                case let .playable(playable):
                    content = playable
                case let .url(url):
                    content = await SonosService.shared.getContent(from: url)
                }
                guard let content else { return }
                let position = [.playlist, .libraryPlaylist].contains(content.content.type) ? .replace : position
                do {
                    try await LocalPlaybackService.shared.enqueue(content, at: position)
                    AlertService.shared.showAlertContent(with: content, subtitle: LocalizedStringKey(position.title), symbolName: "iphone.radiowaves.left.and.right")
                } catch {
                    AlertService.shared.showAlert(with: error.localizedDescription, imageName: "exclamationmark.triangle")
                }
            }
            return true
        } isTargeted: { targeting in
            isTargeted(targeting)
        }
    }
}
