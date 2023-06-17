import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI
import SonosKit

struct SonosWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct SonosWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SonosWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Button("Play Testing", intent: PlayIntent())
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension SonosWidgetAttributes {
    fileprivate static var preview: SonosWidgetAttributes {
        SonosWidgetAttributes(name: "World")
    }
}

extension SonosWidgetAttributes.ContentState {
    fileprivate static var smiley: SonosWidgetAttributes.ContentState {
        SonosWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: SonosWidgetAttributes.ContentState {
         SonosWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: SonosWidgetAttributes.preview) {
   SonosWidgetLiveActivity()
} contentStates: {
    SonosWidgetAttributes.ContentState.smiley
    SonosWidgetAttributes.ContentState.starEyes
}
