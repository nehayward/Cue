import CloudStorage
import VibesDS
import SwiftUI
import SonosKit

struct TimerMenuView: View {
    @Environment(SonosService.self) var sonosService
    @Environment(AlertService.self) var alertService
    @Environment(Router.self) var router

    var group: GroupRoom

    var body: some View {
        Menu {
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
                router.presentedSheet = .customSleepTimer(group: group)
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

