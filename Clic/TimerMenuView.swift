import CloudStorage
import VibesDS
import SwiftUI
import SonosKit

struct TimerMenuView: View {
    @Environment(SonosService.self) var sonosService
    @Environment(AlertService.self) var alertService
    @Environment(Router.self) var router

    var recentTimers: Storage<Duration> = Storage("sleep")
    var group: GroupRoom

    var body: some View {
        Menu {
            if !recentTimers.object.isEmpty {
                ControlGroup {
                    ForEach(recentTimers.object.prefix(3), id: \.self) { timer in
                        Button {
                            Task {
                                await sonosService.sleepTimer(group: group, duration: timer)
                            }
                        } label: {
                            Text(timer.formatted(.units(width: .narrow)))
                        }
                    }
                }.controlGroupStyle(.compactMenu)
            }
            Button {
                Task {
                    await sonosService.sleepTimer(group: group, duration: Duration.seconds(60 * 5))
                }
            } label: {
                Text("5 Minutes")
            }

            Button {
                Task {
                    await sonosService.sleepTimer(group: group, duration: Duration.seconds(60 * 10))
                }
            } label: {
                Text("10 Minutes")
            }

            Button {
                Task {
                    await sonosService.sleepTimer(group: group, duration: Duration.seconds(60 * 15))
                }
            } label: {
                Text("15 Minutes")
            }

            Button {
                Task {
                    await sonosService.sleepTimer(group: group, duration: Duration.seconds(60 * 30))
                }
            } label: {
                Text("30 Minutes")
            }

            Button {
                Task {
                    await sonosService.sleepTimer(group: group, duration: Duration.seconds(60 * 60))
                }
            } label: {
                Text("1 hour")
            }

            Button {
                router.presentedSheet = .customSleepTimer(group: group, recentTimers)
            } label: {
                Text("Custom")
            }

            Button {
                Task {
                    await sonosService.stopSleepTimer(group: group)
                }
            } label: {
                Text("Off")
            }
        } label: {
            Label("Sleep Timer", systemImage: "deskclock.fill")
        }
    }
}

