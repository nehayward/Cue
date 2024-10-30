import Foundation
import SonosKit
import SwiftUI

extension View {
    @MainActor
    func dropDestinationPlay(on group: GroupRoom, now: Bool = true, isTargeted: @escaping (Bool) -> Void = { _ in }) -> some View {
        return dropDestination(for: URL.self) { items, location in
            guard let item = items.first else { return false }
            Task {
                guard let playableContent = await SonosService.shared.getContent(from: item) else { return }
                HapticManager.shared.fireHaptic(.notification(.success))
                do {
                    try await SonosService.shared.queue(playable: playableContent, group: group, position: now ? .now : .next)
                    PlayHistoryService.shared.history.remove(playableContent)
                    PlayHistoryService.shared.history.insert(playableContent, at: 0)
                    if now {
                        await SonosService.shared.play(ip: group.ip)
                    }
                } catch {
                    AlertService.shared.showAlert(with: "Please authorize \(playableContent.content.service.title) in Sonos", imageName: "exclamationmark.triangle.fill")
                }
            }
            return true
        } isTargeted: { targeting in
            isTargeted(targeting)
        }
        .dropDestination(for: PlayableContent.self) { items, location in
            guard let item = items.first else { return false }
            Task {
                HapticManager.shared.fireHaptic(.notification(.success))
                do {
                    try await SonosService.shared.queue(playable: item, group: group, position: now ? .now : .next)
                    if now {
                        await SonosService.shared.play(ip: group.ip)
                    }
                } catch {
                    AlertService.shared.showAlert(with: "Please authorize \(item.content.service.title) in Sonos", imageName: "exclamationmark.triangle.fill")
                }
            }
            return true
        } isTargeted: { targeting in
            isTargeted(targeting)
        }
    }
}
