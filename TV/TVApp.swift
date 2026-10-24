import Defaults
import CloudStorage
import SonosKit
import SubscriptionKit
import SwiftUI
import VibesDS

@main
struct TVApp: App {
    @Environment(\.scenePhase) var scenePhase
    
    private var subscriptionService = SubscriptionService.shared
    private var sonosService = SonosService.shared

    @State private var isLoading: Bool = true
    @State private var showGroup: Bool = false
    @State private var showSettings: Bool = false
    @ObservedObject var value = TVPlayerView.Test()
    @AppStorage("disableScreenSaver") var disableScreenSaver = false
    /// The coordinator of the group the player was last on (`reselect`).
    @State private var lastSelectedID: String?

    public var sorted: [GroupRoom] {
        get {
            return sonosService.groups.sorted { g1, g2 in
                return g1.coordinatorRoom.name < g2.coordinatorRoom.name
            }
        }
        set {
            sonosService.groups = newValue
        }
    }
    
    var body: some Scene {
        WindowGroup {
            @Bindable var sonosService = sonosService
            TabView(selection: $sonosService.selectedGroup) {
                ForEach(sorted) { group in
                    TVPlayerView(group: group, showGroup: $showGroup, showSettings: $showSettings, value: value)
                        .tabItem {
                            Label(group.nameWithCount, systemImage: "hifispeaker.fill")
                        }
                        .tag(group)
                }
            }
            .fullScreenCover(isPresented: $showGroup){
                if let group = sonosService.selectedGroup {
                    TVGroupScreen(coordinatorID: group.coordinatorID)
                } else {
                    if let group = sonosService.sorted.first {
                        TVGroupScreen(coordinatorID: group.coordinatorID)
                    }
                }
            }
            .fullScreenCover(isPresented: $showSettings){
                TVSettingsScreen()
            }
            .environment(sonosService)
            .environment(subscriptionService)
            .tabViewStyle(.tabBarOnly)
            // Never without a selected group while there are groups.
            .onChange(of: sonosService.selectedGroup?.coordinatorID, initial: true) { _, id in
                if let id {
                    lastSelectedID = id
                } else {
                    reselect()
                }
            }
            // Groups that came after none: a search from the welcome screen.
            .onChange(of: sonosService.groups.map(\.coordinatorID)) {
                reselect()
            }
            .task {
                UIApplication.shared.isIdleTimerDisabled = disableScreenSaver
                isLoading = true
                guard let groups = try? await sonosService.getGroupsFast(), !groups.isEmpty else {
                    isLoading = false
                    return
                }
                sonosService.groups = groups
                sonosService.rooms = groups.flatMap(\.rooms)
                sonosService.selectedGroup = sorted.first
                sonosService.monitor()
                isLoading = false
            }
            .overlay {
                if sonosService.sorted.isEmpty, isLoading {
                    Text("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.thickMaterial)
                        .transition(.opacity)
                }
                
                if !isLoading, sonosService.sorted.isEmpty {
                    TVOverviewView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.regularMaterial)
                        .transition(.opacity)
                }
            }
        }
    }

    /// SonosKit lets go of the selected group once its coordinator is no
    /// longer one (a regroup from here or any other controller), and with
    /// nothing selected its poll reads no group's song at all: every tab kept
    /// what it last showed, and a group that formed meanwhile, which has no
    /// song until its first read, stayed blank until a tab was chosen by hand.
    /// The player moves to the group the room it was on is in now, or the
    /// first.
    private func reselect() {
        guard sonosService.selectedGroup == nil, !sonosService.groups.isEmpty else { return }
        let groups = sonosService.groups
        let roomsGroup = lastSelectedID.flatMap { id in
            groups.first { group in group.rooms.contains { $0.id == id } }
        }
        sonosService.selectedGroup = roomsGroup ?? sorted.first
    }
}
