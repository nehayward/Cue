#if canImport(ActivityKit)
import ActivityKit
import Foundation
import SonosKit
import MusicSearchKit
import UIKit
import SwiftUI

final class LiveActivityManager: LiveActivityManageable {    
    private let sonosService: SonosService
    private let artworkManager: ArtworkManager = .shared

    private var createTask: Task<Void,Error>? = nil

    init(sonosService: SonosService = .shared) {
        self.sonosService = sonosService
    }

    func refresh(type: UpdateType = .refresh) async {
        try? await sonosService.load(useCache: true)

        for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
            guard let group = sonosService.groups.first(where: { $0.coordinatorRoom.id == activity.attributes.room.id}) else {
                for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
                    await activity.end(activity.content, dismissalPolicy: .immediate)
                }
                return
            }
            
            if group.coordinatorRoom.track == .empty {
                artworkManager.removeArtwork(coordinatorRoom: group.nameWithCount)
            } else {
                await artworkManager.downScale(coordinatorRoom: group.nameWithCount, url: group.coordinatorRoom.track.artworkURL)
            }

            var tvSettings: TVSettings?
            if group.TVMode {
                tvSettings = try? await sonosService.getTVSettings(ip: group.ip)
            }
            
            

            let contentState = ClicNowPlayingWidgetAttributes.ContentState(
                playableContent: group.coordinatorRoom.track.toPlayable,
                volume: group.groupVolume,
                isMuted: group.isMuted,
                name: group.nameWithCount,
                update: type,
                TVMode: group.TVMode,
                TVSettings: tvSettings
            )

            let activityContent = ActivityContent(state: contentState, staleDate: Date.now.addingTimeInterval(60))
            await activity.update(activityContent)
        }
    }

    func createActivity() {
        createTask?.cancel()
        createTask = Task {
            if Task.isCancelled { return }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let activities = Activity<ClicNowPlayingWidgetAttributes>.activities
            try? await sonosService.load(useCache: true)

            for group in sonosService.groups.filter({ $0.coordinatorRoom.isPlaying || $0.TVMode }) {
                guard !activities.contains(where: { $0.attributes.room.id == group.coordinatorRoom.id }) else {
                    continue
                }

                await artworkManager.downScale(coordinatorRoom: group.nameWithCount, url: group.coordinatorRoom.track.artworkURL)

                let sonosAttribute = ClicNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: group.coordinatorRoom.id,
                                                                                            ip: group.coordinatorRoom.ip,
                                                                                            name: group.nameWithCount))


                var tvSettings: TVSettings?
                if group.TVMode {
                    tvSettings = try? await sonosService.getTVSettings(ip: group.ip)
                }

                let contentState = ClicNowPlayingWidgetAttributes.ContentState(
                    playableContent: group.coordinatorRoom.track.toPlayable,
                    volume: group.groupVolume,
                    isMuted: group.isMuted,
                    name: group.nameWithCount,
                    TVMode: group.TVMode,
                    TVSettings: tvSettings
                )

                let activityContent = ActivityContent(state: contentState, staleDate: Date.now.addingTimeInterval(60), relevanceScore: Double(activities.count))


                do {
                    if Task.isCancelled { return }
                    let activity = try Activity.request(attributes: sonosAttribute, content: activityContent)
                    print("Created Live Activity for \(activity.content) \(activity.attributes)")
                } catch (let error) {
                    print("Error requesting Live Activity \(error.localizedDescription).")
                }
            }
        }
    }

    func createActivity(id: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let activities = Activity<ClicNowPlayingWidgetAttributes>.activities
        try? await sonosService.load(useCache: true)

        guard let group = await sonosService.getGroupCoordinatorWithRoom(roomID: id) else {
            return
        }

        let sonosAttribute = ClicNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: group.coordinatorRoom.id,
                                                                                    ip: group.coordinatorRoom.ip,
                                                                                    name: group.nameWithCount))

        var tvSettings: TVSettings?
        if group.TVMode {
            tvSettings = try? await sonosService.getTVSettings(ip: group.ip)
        }

        let contentState = ClicNowPlayingWidgetAttributes.ContentState(
            playableContent: group.coordinatorRoom.track.toPlayable,
            volume: group.groupVolume,
            isMuted: group.isMuted,
            name: group.nameWithCount,
            TVMode: group.TVMode,
            TVSettings: tvSettings
        )
        
        let activityContent = ActivityContent(state: contentState, staleDate: Date.now.addingTimeInterval(60), relevanceScore: activities.isEmpty ? 0 : 1)
        guard !activities.contains(where: { $0.attributes.room.id == group.coordinatorRoom.id }) else {
            print("Failed")
            return
        }

        do {
            let activity = try Activity.request(attributes: sonosAttribute, content: activityContent)
            print("Created Live Activity from ID: \(activity.content) \(activity.attributes)")
        } catch (let error) {
            print("Error requesting Live Activity \(error.localizedDescription).")
        }
    }

    func reset() {
        for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
            Task {
                await activity.end(activity.content, dismissalPolicy: .immediate)
            }
        }
    }
}

#endif
