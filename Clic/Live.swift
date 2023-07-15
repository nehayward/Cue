
import ActivityKit
import Foundation

class LiveActivityManager {

    static var shared = LiveActivityManager()

    var activity: Activity<SonosWidgetAttributes>?

    func okay() {
        print(ActivityAuthorizationInfo().areActivitiesEnabled)
    }

    func refresh() {
        let contentState = SonosWidgetAttributes.ContentState(emoji: "💩")
        let activityContent = ActivityContent(state: contentState, staleDate: nil)
        Task {
           await activity?.update(activityContent)
        }

    }

    func createActivity() {
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            // Create the activity attributes and activity content objects.
            // ...
            
            
            // Start the Live Activity.
            
            
            let sonosAttribute = SonosWidgetAttributes(date: .now, name: "Garage", speaker: "192.168.4.50", ip: "", isPlaying: false,  sonosSpeaker: SonosSpeakerEntity(id: "", name: "Garage", ip: "192.168.4.50", volume: 0), volume: 0)
            let contentState = SonosWidgetAttributes.ContentState(emoji: "🥳")
            let activityContent = ActivityContent(state: contentState, staleDate: nil)
            do {
                
                activity = try Activity.request(attributes: sonosAttribute, content: activityContent)
                print("Requested a pizza delivery Live Activity \(String(describing: activity?.id)).")
                
            } catch (let error) {
                print("Error requesting pizza delivery Live Activity \(error.localizedDescription).")
            }
            Task {
                for await activity in Activity<SonosWidgetAttributes>.activityUpdates {
                    print("Pizza delivery details: \(activity.attributes)")
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
