import SwiftUI
import WatchKit

/// Cue on Apple Watch: Plex and Subsonic music downloaded to the watch and
/// played from it. What's here is chosen on the watch (its home screen
/// browses the servers with the sign-ins the iPhone shared) or on the
/// iPhone (Add to Apple Watch); the watch fetches it from the server itself,
/// and Fast Download does that over Wi‑Fi.
@main
struct CueWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = WatchDownloadStore.shared
    @State private var player = WatchPlayer.shared
    @State private var accounts = WatchAccounts.shared

    var body: some Scene {
        WindowGroup {
            LibraryScreen()
                .environment(store)
                .environment(player)
                .environment(accounts)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.appDidBecomeActive()
            case .background:
                store.appDidEnterBackground()
                WidgetStatePublisher.publishNow()
            default:
                break
            }
        }
    }
}

@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        PhoneConnection.shared.activate()
        // Makes the store, and with it the background session, so events
        // for transfers that finished while Cue was closed are delivered.
        _ = WatchDownloadStore.shared
        // Nothing's playing yet, whatever the widgets were last told.
        WidgetStatePublisher.publishNow()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let sessionTask as WKURLSessionRefreshBackgroundTask
                where sessionTask.sessionIdentifier == WatchDownloadStore.backgroundIdentifier:
                WatchDownloadStore.shared.handleBackgroundEvents {
                    sessionTask.setTaskCompletedWithSnapshot(false)
                }
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                PhoneConnection.shared.hold(connectivityTask)
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
