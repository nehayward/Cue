import ActivityKit
import Foundation
import Kingfisher
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
