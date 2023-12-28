import CloudStorage
import RevenueCat
import RevenueCatUI
import SonosKit
import SubscriptionKit
import StoreKit
import SwiftUI
import WidgetKit

@main
struct ClicApp: App {
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.requestReview) var requestReview

    @State private var selected: Route?
    @State private var liveActivityManager: LiveActivityManager? = nil
    @State private var subscriptionService = SubscriptionService()
    @State private var sonosService = SonosService()
    @State private var alertService = AlertService()
    @State private var showPaywall = false

    @CloudStorage("com.clic.subscriptions") private var activeSubscription: Bool = false
    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some Scene {
        WindowGroup {
            DeviceListMainView(selected: $selected)
                .environment(sonosService)
                .environment(subscriptionService)
                .environment(alertService)
                .task {
                    liveActivityManager = LiveActivityManager(sonosService: sonosService)
                    subscriptionService.monitorChanges()
                }
                .onOpenURL(perform: handle)
                .sheet(isPresented: $showPaywall) {
                    PaywallView()
                }
        }
        .onChange(of: scenePhase) {
            handleScenePhase(scenePhase)
        }
        .onChange(of: sonosService.sorted.map(\.coordinatorRoom.isPlaying), initial: false) {
            guard subscriptionService.subscription.isActive else { return }
            liveActivityManager?.createActivity()
        }
        .onChange(of: subscriptionService.subscription, initial: true) { oldValue, newValue in
            activeSubscription =  newValue.isActive
        }
    }

    @MainActor
    private func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            sonosService.monitor()
            if !subscriptionService.subscription.isActive {
                return
            }
            
            Task {
                await liveActivityManager?.refresh()
            }

            Task {
                try? await subscriptionService.checkSubscription()
            }

            guard ReviewService().askForRequest() else { return }
            requestReview()

//            // MARK: Add back when monitoring is fixed
//            Task { @MainActor in
//                try? await sonosService.updateGroupsCheckPlayback()
//
//                if selected == nil {
//                    let playingGroups = sonosService.groups.filter(\.coordinatorRoom.isPlaying)
//                    if playingGroups.count == 1, let groupPlaying = playingGroups.first {
//                        try await Task.sleep(for: .milliseconds(200))
//                        alertService.showAlert(with: "Jumped to \(groupPlaying.coordinatorRoom.name)")
//                        selected = groupPlaying.coordinatorID
//                    }
//                }
//            }
        case .inactive:
            print("Inactive")
            WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
            Task {
                await liveActivityManager?.refresh()
            }
        case .background:
            print("Background")
            Task {
                sonosService.sonosPulse.cancel()
            }
        @unknown default:
            break
        }
    }

    private func handle(_ url: URL) {
        guard let url = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        if url.host?.lowercased() == "subscribe" {
            showPaywall = true
            return
        }

        if url.host?.lowercased() == "search", let id = url.queryItems?.first(where: { $0.name == "id" })?.value {
            if sonosService.groups.contains(where:  { $0.coordinatorRoom.id == id} ) {
                selected = Route(id: id, search: true)
                return
            }
            Task {
                try await sonosService.fetch(useCache: true)
                if sonosService.groups.contains(where:  { $0.coordinatorRoom.id == id} ) {
                    selected = Route(id: id, search: true)
                }
            }
        }

        if url.host?.lowercased() == "device", let id = url.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty {
            if sonosService.groups.contains(where:  { $0.coordinatorRoom.id == id} ) {
                selected = Route(id: id, search: false)
                return
            }
            Task {
                try await sonosService.fetch(useCache: true)
                if sonosService.groups.contains(where:  { $0.coordinatorRoom.id == id} ) {
                    selected = Route(id: id, search: false)
                }
            }
        }
    }
}
