import ActivityKit
import Foundation
import Kingfisher
import SonosKit

final class LiveActivityManager {
    let sonosService: SonosService
    var activity: Activity<ClicNowPlayingWidgetAttributes>?
    var activitySequence: Task<Void,Error>?

    init(sonosService: SonosService) {
        self.sonosService = sonosService
        monitorActivities()
    }

    func refresh() async {
        try? await sonosService.fetch(useCache: true)
        let groups = sonosService.groups
        //        guard let group = groups.filter ({ $0.coordinatorRoom.name == "Garage" }).first else {

        for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
            guard let group = groups.first(where: { $0.coordinatorRoom.id == activity.attributes.room.id}) else {
                for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
                    await activity.end(activity.content, dismissalPolicy: .after(.now.addingTimeInterval(60)))
                    self.activity = nil
                }

                return
            }

            let contentState = ClicNowPlayingWidgetAttributes.ContentState(trackName: group.coordinatorRoom.track.name,
                                                                           artist: group.coordinatorRoom.track.artist,
                                                                           volume: group.groupVolume)
            let activityContent = ActivityContent(state: contentState, staleDate: nil)
            await activity.update(activityContent)
        }
    }

    func createActivity(with groups: [GroupRoom]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard let group = groups.first(where: \.coordinatorRoom.isPlaying) else {
//        guard let group = groups.filter ({ $0.coordinatorRoom.name == "Garage" }).first else {
            Task {
                for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
                    await activity.end(activity.content, dismissalPolicy: .after(.now.addingTimeInterval(60)))
                    self.activity = nil
                }
            }
            return
        }

        if activity != nil {
            return
        }

        let sonosAttribute = ClicNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: group.coordinatorRoom.id,
                                                                                    name: group.coordinatorRoom.name,
                                                                                    ip: group.coordinatorRoom.ip,
                                                                                    volume: group.groupVolume))

        let contentState = ClicNowPlayingWidgetAttributes.ContentState(trackName: group.coordinatorRoom.track.name,
                                                                       artist: group.coordinatorRoom.track.artist,
                                                                       volume: group.groupVolume
        )
        let activityContent = ActivityContent(state: contentState, staleDate: nil)
        do {
            activity = try Activity.request(attributes: sonosAttribute, content: activityContent)
            //                print("Started", activity?.id)
        } catch (let error) {
            print("Error requesting Live Activity \(error.localizedDescription).")
        }
    }

    private func monitorActivities() {
        activitySequence = Task {
            for await activity in Activity<ClicNowPlayingWidgetAttributes>.activityUpdates {
                print("Created Live Activity for \(activity.content) \(activity.attributes)")
            }
        }
    }
}
