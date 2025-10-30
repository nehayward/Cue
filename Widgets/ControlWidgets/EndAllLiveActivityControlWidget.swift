//
//  RemoteControlWidget 2.swift
//  Clic
//
//  Created by Nick Hayward on 10/30/25.
//


import AppIntents
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct EndAllLiveActivityControlWidget: ControlWidget {
    static let kind: String = "com.clic.EndAllLiveActivities"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            intent: EndAllLiveActivitiesIntent.self
        ) { configuration in
            ControlWidgetButton(action: configuration) {
                Image(systemName: "inset.filled.capsule")
                Text("End All")
            }
        }
        .displayName("End All Live Activities")
        .description("End all active Live Activities for Sonos speakers.")
    }
}
