import Foundation
import SonosKit
import SwiftUI

extension View {
    @MainActor
    func dropDestinationPlay(on group: GroupRoom, now: Bool = true, isTargeted: @escaping (Bool) -> Void = { _ in }) -> some View {
        dropDestination(for: URL.self) { items, location in
            guard let url = items.first else { return false }
            Task {
                guard let playableContent = await SonosService.shared.getContent(from: url) else { return }
                HapticManager.shared.fireHaptic(.notification(.success))
                await SonosService.shared.queue(playable: playableContent, group: group, position: now ? .now : .next)
                if now {
                    await SonosService.shared.play(ip: group.ip)
                }
            }
            return true
        } isTargeted: { targeting in
            isTargeted(targeting)
        }
    }

    @MainActor
    func dropDestinationPlayableContentPlay(on group: GroupRoom, now: Bool = true, isTargeted: @escaping (Bool) -> Void = { _ in }) -> some View {
        dropDestination(for: PlayableContent.self) { items, location in
            guard let playableContent = items.first else { return false }
            Task {
                HapticManager.shared.fireHaptic(.notification(.success))
                await SonosService.shared.queue(playable: playableContent, group: group, position: now ? .now : .next)
                if now {
                    await SonosService.shared.play(ip: group.ip)
                }
            }
            return true
        } isTargeted: { targeting in
            isTargeted(targeting)
        }
    }
}
