import Foundation
import SonosKit
import SwiftUI

extension View {
    @MainActor
    func dropDestinationPlay(on group: GroupRoom, position: QueuePosition = .now, isTargeted: @escaping (Bool) -> Void = { _ in }) -> some View {
        return dropDestination(for: MultiTypeTransferable.self) { items, _ in
            DropPlay.onGroup(items, group: group, position: position)
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
            DropPlay.onDevice(items, position: position)
        } isTargeted: { targeting in
            isTargeted(targeting)
        }
    }

    /// Either of the two, by `group`: on that speaker, or on this device
    /// when it's nil. One modifier whichever it is, so a view that follows
    /// the route keeps its identity — and its state — when the route
    /// changes, where choosing between the two above in an `if` built it
    /// again.
    @MainActor
    func dropDestinationPlay(onGroupOrDevice group: GroupRoom?, position: QueuePosition = .now, isTargeted: @escaping (Bool) -> Void = { _ in }) -> some View {
        return dropDestination(for: MultiTypeTransferable.self) { items, _ in
            if let group {
                return DropPlay.onGroup(items, group: group, position: position)
            }
            return DropPlay.onDevice(items, position: position)
        } isTargeted: { targeting in
            isTargeted(targeting)
        }
    }
}

/// What a drop does, shared by the modifiers above. The work goes on the
/// main actor, where the queues live.
private enum DropPlay {
    static func onGroup(_ items: [MultiTypeTransferable], group: GroupRoom, position: QueuePosition) -> Bool {
        print(items)
        guard let item = items.first else { return false }
        switch item {
        case let .playable(content):
            Task { @MainActor in
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
            Task { @MainActor in
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
    }

    static func onDevice(_ items: [MultiTypeTransferable], position: QueuePosition) -> Bool {
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
                // A station plays now wherever it's dropped (`enqueue`).
                let shown: QueuePosition = content.content.type.isRadio ? .now : position
                AlertService.shared.showAlertContent(with: content, subtitle: LocalizedStringKey(shown.title), symbolName: "iphone.radiowaves.left.and.right")
            } catch {
                AlertService.shared.showAlert(with: error.localizedDescription, imageName: "exclamationmark.triangle")
            }
        }
        return true
    }
}
