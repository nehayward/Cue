import ActivityKit
import Foundation
import SonosKit

final class LiveActivityManager {
    let sonosService: SonosService
    var activity: Activity<ClicNowPlayingWidgetAttributes>?

    init(sonosService: SonosService) {
        self.sonosService = sonosService
    }

    func okay() {
        print(ActivityAuthorizationInfo().areActivitiesEnabled)
    }

    func refresh() async {
        let groups = sonosService.groups
//        guard let group = groups.filter ({ $0.coordinatorRoom.name == "Garage" }).first else {
        guard let group = groups.first(where: \.coordinatorRoom.isPlaying) else {
            for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
                await activity.end(activity.content, dismissalPolicy: .after(.now.addingTimeInterval(60)))
                self.activity = nil
            }

            return
        }

        for activity in Activity<ClicNowPlayingWidgetAttributes>.activities {
            print(group.groupVolume)
            let sonosAttribute = ClicNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: group.coordinatorRoom.id, name: group.coordinatorRoom.name, ip: group.coordinatorRoom.ip, volume: group.groupVolume))
            let contentState = ClicNowPlayingWidgetAttributes.ContentState(date: .now, isPlaying: true, trackName: group.coordinatorRoom.track.name, imageData: Data(), volume: group.groupVolume)
            let activityContent = ActivityContent(state: contentState, staleDate: nil)
            await activity.update(activityContent)
        }
    }
    
    func createActivity(with groups: [GroupRoom]) {
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            guard let group = groups.first(where: \.coordinatorRoom.isPlaying) else {
//            guard let group = groups.filter ({ $0.coordinatorRoom.name == "Garage" }).first else {
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

            let sonosAttribute = ClicNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: group.coordinatorRoom.id, name: group.coordinatorRoom.name, ip: group.coordinatorRoom.ip, volume: group.groupVolume))
            let contentState = ClicNowPlayingWidgetAttributes.ContentState(date: .now, isPlaying: true, trackName: group.coordinatorRoom.track.name, imageData: Data(), volume: group.groupVolume)
            let activityContent = ActivityContent(state: contentState, staleDate: nil)
            do {
                activity = try Activity.request(attributes: sonosAttribute, content: activityContent)
                //                print("Started", activity?.id)
            } catch (let error) {
                print("Error requesting Live Activity \(error.localizedDescription).")
            }
            Task {
                for await activity in Activity<ClicNowPlayingWidgetAttributes>.activityUpdates {
                    print("Created Live Activity for \(group.coordinatorRoom.name) \(activity.attributes)")
                }
            }
        }

        //    if let activity = try? Activity.request(attributes: activityAttributes,
        //                                            content: activityContent,
        //      // Setting your pushType as .token allows the Activity to generate push tokens for the server to watch.
        //                                            pushType: .token) {
        //      // Register your Live Activity with Braze using the pushTokenTag
        //      AppDelegate.braze?.liveActivities.launchActivity(pushTokenTag: "live-activity-1",
        //                                                       activity: activity)
    }
}
