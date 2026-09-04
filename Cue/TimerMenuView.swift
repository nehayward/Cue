import SwiftUI
import SonosKit

struct TimerMenuView<Label: View>: View {
    @State var router = Router()

    var recentTimers: Storage<Duration> = Storage("sleep")
    var inMainMenu: Bool = false
    /// Whose sheet "Custom" presents on, when neither this menu's own nor
    /// the main window's will do: a menu nested in another menu can't host
    /// a sheet, and the local player sits in a full-screen cover the main
    /// window's sheets would come up behind.
    var sheetRouter: Router? = nil
    var onSelect: (Duration) async -> Void
    var onClear: (() async -> Void)? = nil
    /// When set, shows an "End of Song" item that sleeps at the end of the
    /// current track. Omitted where there's no live playback (e.g. Scenes).
    var onSleepAtEndOfTrack: (() async -> Void)? = nil

    @ViewBuilder var label: Label

    var body: some View {
        Menu {
            if !recentTimers.object.isEmpty {
                ControlGroup {
                    ForEach(recentTimers.object.prefix(3), id: \.self) { timer in
                        Button {
                            Task { await onSelect(timer) }
                        } label: {
                            Text(timer.formatted(.units(width: .narrow)))
                        }
                    }
                }.controlGroupStyle(.compactMenu)
            }

            if let onSleepAtEndOfTrack {
                Button("End of Song") {
                    Task { await onSleepAtEndOfTrack() }
                }
            }

            Button("5 Minutes") { Task { await onSelect(.seconds(60 * 5)) } }
            Button("10 Minutes") { Task { await onSelect(.seconds(60 * 10)) } }
            Button("15 Minutes") { Task { await onSelect(.seconds(60 * 15)) } }
            Button("30 Minutes") { Task { await onSelect(.seconds(60 * 30)) } }
            Button("1 Hour") { Task { await onSelect(.seconds(60 * 60)) } }

            Button("Custom") {
                if let sheetRouter {
                    sheetRouter.presentedSheet = .customSleepTimer(recentTimers: recentTimers, onSelect: onSelect)
                } else if inMainMenu {
                    Router.main.presentedSheet = .customSleepTimer(recentTimers: recentTimers, onSelect: onSelect)
                } else {
                    router.presentedSheet = .customSleepTimer(recentTimers: recentTimers, onSelect: onSelect)
                }
            }

            if let onClear {
                Button("Off") { Task { await onClear() } }
            }
        } label: {
            label
        }
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }
}
