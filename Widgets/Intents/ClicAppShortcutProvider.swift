import AppIntents

struct ClicAppShortcutProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .teal }
    
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
            intent: LaunchAlarmsIntent(),
            phrases: [
                "Open \(.applicationName) Alarms"
            ],
            shortTitle: "Open Alarms",
            systemImageName: "alarm"
        )
    }
}

