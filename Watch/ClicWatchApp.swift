import SwiftUI
import SonosKit
import WidgetKit

@main
struct ClicWatchApp: App {
    @Environment(\.scenePhase) var scenePhase
    @State var selected: String?

    var sonosService = SonosService()
    var popOver = Popover()

    var body: some Scene {
        WindowGroup {
            ContentView(selected: $selected)
                .environment(popOver)
                .environment(sonosService)
                .task {
                    sonosService.monitorWatch()
                }
                .overlay {
                    VStack {
                        Text(!sonosService.monitorTask.isCancelled ? "Running" : "Cancelled")
                            .bold()
                        Spacer()
                    }
                    .ignoresSafeArea()
                }
                .safeAreaInset(edge: .bottom) {
                    if sonosService.systemNotFound {
                        Button {
                            sonosService.monitorWatch()
                        } label: {
                            Text("No System Found. Search")
                                .padding()
                                .background {
                                    Capsule()
                                        .foregroundStyle(.thinMaterial)
                                }
                        }
                        .transition(.move(edge: .bottom).combined(with: .scale(0.8)))
                        .padding()
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                .animation(.bouncy, value: sonosService.networkMonitorService.isConnected)
                .animation(.spring, value: sonosService.systemNotFound)
                .animation(.smooth, value: sonosService.groups)
        }.onChange(of: scenePhase) {
            if scenePhase == .active {
                Task {
                    if selected == nil {
                        selected = sonosService.groups.first(where: { room in
                            room.coordinatorRoom.isPlaying
                        })?.coordinatorID
                        return
                    }
                    for group in sonosService.groups {
                        let playbackInfo = await sonosService.getPlaybackInfo(ip: group.coordinatorRoom.ip)
                        switch playbackInfo {
                        case .playing:
                            group.coordinatorRoom.isPlaying = true
                        case .paused:
                            group.coordinatorRoom.isPlaying = false
                        default:
                            break
                        }
                    }
                    if selected == nil {
                        selected = sonosService.groups.first(where: { room in
                            room.coordinatorRoom.isPlaying
                        })?.coordinatorID
                    }
                }
            }
        }
    }
}
