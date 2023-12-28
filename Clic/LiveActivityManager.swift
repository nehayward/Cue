import ActivityKit
import Foundation
import Kingfisher
import SonosKit

final class LiveActivityManager {
    private let sonosService: SonosService
    private var createTask: Task<Void,Error>? = nil

    init(sonosService: SonosService) {
        self.sonosService = sonosService
    }

    func refresh(updateType: UpdateType = .refresh) async {
        try? await sonosService.fetch(useCache: true)
        let groups = sonosService.groups

        for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
            guard let group = groups.first(where: { $0.coordinatorRoom.id == activity.attributes.room.id}) else {
                for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
                    await activity.end(activity.content, dismissalPolicy: .immediate)
                }

                return
            }

            let contentState = ClicNowPlayingWidgetAttributes.ContentState(trackName: group.coordinatorRoom.track.name,
                                                                           artist: group.coordinatorRoom.track.artist,
                                                                           volume: group.groupVolume,
                                                                           name: group.nameWithCount,
                                                                           update: updateType)
            let activityContent = ActivityContent(state: contentState, staleDate: nil)
            await activity.update(activityContent)
        }
    }

    func createActivity() {
        createTask?.cancel()
        createTask = Task {
            if Task.isCancelled { return }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let activities = Activity<ClicNowPlayingWidgetAttributes>.activities
            try? await sonosService.fetch(useCache: true)
            for group in sonosService.groups.filter(\.coordinatorRoom.isPlaying) {
                let sonosAttribute = ClicNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: group.coordinatorRoom.id,
                                                                                            ip: group.coordinatorRoom.ip,
                                                                                            name: group.coordinatorRoom.name,
                                                                                            volume: group.groupVolume))

                let contentState = ClicNowPlayingWidgetAttributes.ContentState(trackName: group.coordinatorRoom.track.name,
                                                                               artist: group.coordinatorRoom.track.artist,
                                                                               volume: group.groupVolume,
                                                                               name: group.nameWithCount)

                let activityContent = ActivityContent(state: contentState, staleDate: nil, relevanceScore: Double(activities.count))
                guard !activities.contains(where: { $0.attributes.room.id == group.coordinatorRoom.id }) else {
                    print("HERE")
                    return
                }

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
        try? await sonosService.updateGroups()

        guard let group = await sonosService.getGroupCoordinatorWithRoom(roomID: id) else {
            return
        }

        let sonosAttribute = ClicNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: group.coordinatorRoom.id,
                                                                                    ip: group.coordinatorRoom.ip,
                                                                                    name: group.nameWithCount,
                                                                                    volume: group.groupVolume))

        let contentState = ClicNowPlayingWidgetAttributes.ContentState(trackName: group.coordinatorRoom.track.name,
                                                                       artist: group.coordinatorRoom.track.artist,
                                                                       volume: group.groupVolume,
                                                                       name: group.nameWithCount)

        let activityContent = ActivityContent(state: contentState, staleDate: nil, relevanceScore: activities.isEmpty ? 0 : 1)
        guard !activities.contains(where: { $0.attributes.room.id == group.coordinatorRoom.id }) else {
            print("Failed")
            return
        }
        print(activities)

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
