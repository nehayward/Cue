import ActivityKit
import Foundation
import Kingfisher
import SonosKit

final class LiveActivityManager {
    let sonosService: SonosService
    var activitySequence: Task<Void,Error>?

    init(sonosService: SonosService) {
        self.sonosService = sonosService
        monitorActivities()
    }

    func refresh(updateType: UpdateType = .refresh) async {
        try? await sonosService.fetch(useCache: true)
        let groups = sonosService.groups

        for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
            guard let group = groups.first(where: { $0.coordinatorRoom.id == activity.attributes.room.id}) else {
                for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
                    await activity.end(activity.content, dismissalPolicy: .after(.now.addingTimeInterval(60)))
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

    func createActivity() async {
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

            let activityContent = ActivityContent(state: contentState, staleDate: nil)
            guard !activities.contains(where: { $0.attributes.room.id == group.coordinatorRoom.id }) else {
                print("HERE")
                return
            }

            do {
                try Activity.request(attributes: sonosAttribute, content: activityContent)
            } catch (let error) {
                print("Error requesting Live Activity \(error.localizedDescription).")
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

        let activityContent = ActivityContent(state: contentState, staleDate: nil)
        guard !activities.contains(where: { $0.attributes.room.id == group.coordinatorRoom.id }) else {
            print("Failed")
            return
        }

        do {
            try Activity.request(attributes: sonosAttribute, content: activityContent)
        } catch (let error) {
            print("Error requesting Live Activity \(error.localizedDescription).")
        }
    }

    private func monitorActivities() {
        activitySequence?.cancel()
        activitySequence = Task {
            for await activity in Activity<ClicNowPlayingWidgetAttributes>.activityUpdates {
                print("Created Live Activity for \(activity.content) \(activity.attributes)")
            }
        }
    }
}
