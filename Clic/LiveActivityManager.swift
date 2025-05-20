#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
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

    func refresh() async {
        for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
            guard let group = sonosService.groups.first(where: { $0.coordinatorRoom.id == activity.attributes.room.id}) else {
                for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
                    await activity.end(activity.content, dismissalPolicy: .immediate)
                }
                return
            }

            async let track =  sonosService.getTrack(ip: group.coordinatorRoom.ip)
            async let playbackInfo = sonosService.getPlaybackInfo(ip: group.coordinatorRoom.ip)
            async let groupVolume = sonosService.getGroupVolume(ip: group.coordinatorRoom.ip)
            
            guard let info = try? await (track, playbackInfo, groupVolume) else { return }
            if let track = info.0 {
                if group.coordinatorRoom.track == track, !group.isEditingPlayback, group.coordinatorRoom.track.playbackPosition != track.playbackPosition  {
                    group.coordinatorRoom.track.playbackPosition = track.playbackPosition
                } else {
                    group.coordinatorRoom.track = track
                }
            }
            group.coordinatorRoom.isPlaying = info.1 == .playing
            group.groupVolume = info.2
            
            if group.coordinatorRoom.track == .empty {
                artworkManager.removeArtwork(coordinatorRoom: group.nameWithCount)
            } else {
                await artworkManager.downScale(coordinatorRoom: group.nameWithCount, url: group.coordinatorRoom.track.artworkURL, trackID: group.coordinatorRoom.track.trackID)
            }

            if group.TVMode {
                group.tvSettings = try? await sonosService.getTVSettings(ip: group.ip)
            }
            
            let contentState = group.toContentState
            let activityContent = ActivityContent(state: contentState, staleDate: .now.addingTimeInterval(1))
            await activity.update(activityContent)
            
//            if !group.coordinatorRoom.isPlaying && !group.TVMode {
//                await activity.end(activity.content, dismissalPolicy: .after(.now.addingTimeInterval(60)))
//            }
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

                await ArtworkManager.shared.downScale(coordinatorRoom: group.nameWithCount, url: group.coordinatorRoom.track.artworkURL, trackID: group.coordinatorRoom.track.trackID)

                let sonosAttribute = ClicNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: group.coordinatorRoom.id,
                                                                                            ip: group.coordinatorRoom.ip,
                                                                                            name: group.nameWithCount))
                if group.TVMode {
                    group.tvSettings = try? await sonosService.getTVSettings(ip: group.ip)
                }

                let contentState = group.toContentState
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

        if group.TVMode {
            group.tvSettings = try? await sonosService.getTVSettings(ip: group.ip)
        }

        let contentState = group.toContentState
        
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

    func reset() async {
        for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
    }
    
    func stop(id: String) async {
        for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
            if id == activity.attributes.room.id {
                await activity.end(activity.content, dismissalPolicy: .immediate)
            }
        }
    }
    
    func toggle(id: String) async {
        for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
            guard let _ = sonosService.groups.first(where: { $0.coordinatorRoom.id == activity.attributes.room.id}) else {
                continue
            }

            await activity.end(activity.content, dismissalPolicy: .immediate)
            return
        }
        
        await createActivity(id: id)
    }
}

#endif
