import AppIntents

struct ClicAppShortcutProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .grayBlue }

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunSceneIntent(askForScene: true),
            phrases: [
                "Run Scene in \(.applicationName)"
            ],
            shortTitle: "Run Scene",
            systemImageName: "bolt.fill"
        )

        AppShortcut(
            intent: RunSceneIntent(askForScene: true),
            phrases: [
                "Run \(\.$scene) in \(.applicationName)"
            ],
            shortTitle: "Run Scene",
            systemImageName: "bolt.fill"
        )

        AppShortcut(
            intent: LaunchAlarmsIntent(),
            phrases: [
                "Open \(.applicationName) Alarms"
            ],
            shortTitle: "Open Alarms",
            systemImageName: "alarm"
        )

        AppShortcut(
            intent: LaunchSpeakerIntent(),
            phrases: [
                "Launch \(\.$room) with \(.applicationName)"
            ],
            shortTitle: "Launch Speaker",
            systemImageName: "hifispeaker.fill"
        )

        AppShortcut(
            intent: PlaybackIntent(requestRoom: true),
            phrases: [
                "\(\.$playback) with \(.applicationName)"
            ],
            shortTitle: "Pause Room",
            systemImageName: "pause.fill"
        )
        
        AppShortcut(
            intent: EndAllLiveActivitiesIntent(),
            phrases: [
                "End all live activities in \(.applicationName)"
            ],
            shortTitle: "End All Live Activities",
            systemImageName: "inset.filled.capsule"
        )

        AppShortcut(
            intent: SetSleepTimerIntent(requestRoom: true),
            phrases: [
                "Set sleep timer in \(.applicationName)",
                "Set \(\.$duration) sleep timer in \(.applicationName)"
            ],
            shortTitle: "Set Sleep Timer",
            systemImageName: "moon.zzz.fill"
        )

        AppShortcut(
            intent: StopSleepTimerIntent(requestRoom: true),
            phrases: [
                "Stop sleep timer in \(.applicationName)",
                "Cancel sleep timer in \(.applicationName)"
            ],
            shortTitle: "Stop Sleep Timer",
            systemImageName: "moon.zzz"
        )
    }
}
