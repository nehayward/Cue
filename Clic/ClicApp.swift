import CloudStorage
import RevenueCat
import RevenueCatUI
import SonosKit
import SubscriptionKit
import MusicKit
import MusicSearchKit
import StoreKit
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

@main
struct ClicApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @Environment(\.scenePhase) var scenePhase
    @Environment(\.requestReview) var requestReview
    @Environment(\.liveActivityManager) var liveActivityManager

    @State private var router: Router = Router()
    @State private var subscriptionService = SubscriptionService.shared
    @State private var sonosService = SonosService.shared
    @State private var alertService = AlertService.shared

    @CloudStorage("com.clic.subscriptions") private var activeSubscription: Bool = false
    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    @State var selectedID: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if OSEnvironment.pad || UIDevice.current.userInterfaceIdiom == .vision {
                    HStack {
                        SidebarSplitView {
                            ListViewLarge(selected: $selectedID)
                            ContainerLargePlayerView(id: $selectedID)
                                .toolbar {
                                    ToolbarItemGroup(placement: .primaryAction) {
                                        if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .vision {
                                            Button {
                                                if let id = selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                                                    if router.inspectorSheet != .search(group: sonosService.sorted[group], instant: false) {
                                                        router.inspectorSheet = .search(group: sonosService.sorted[group], instant: false)
                                                    } else {
                                                        router.inspectorSheet = nil
                                                    }
                                                }
                                            } label: {
                                                Image(systemName: "sparkle.magnifyingglass")
                                                    .tint(.primary)
                                            }

                                            Button {
                                                if let id = selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                                                    if router.inspectorSheet != .queue(group: $sonosService.sorted[group]) {
                                                        router.inspectorSheet = .queue(group: $sonosService.sorted[group])
                                                    } else {
                                                        router.inspectorSheet = nil
                                                    }
                                                }
                                            } label: {
                                                Image(systemName: "list.dash")
                                                    .tint(.primary)
                                            }
                                        }
                                    }
                                }
                        }
                        .ignoresSafeArea()
#if os(visionOS)
                        .ornament(visibility: .visible, attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
                            Group {
                                switch router.inspectorSheet {
                                case let .search(group, instant):
                                    NewSearchScreen(group: group, instant: instant)
                                case let .queue(group):
                                    QueueScreen(group: group)
                                default:
                                    EmptyView()
                                        .onAppear {
                                            router.inspectorSheet = nil
                                        }
                                }
                            }
                            .glassBackgroundEffect()
                            .frame(minWidth: 400, minHeight: 800)
                            .offset(x: router.inspectorSheet != nil ? 0 : -400)
                            .offset(z: router.inspectorSheet != nil ? 0 : -64)
                            .opacity(router.inspectorSheet != nil ? 1 : 0)
                            .animation(.spring, value: router.inspectorSheet)
                        }
#endif
#if !os(visionOS)
                        .withInspector(inspectorDestination: $router.inspectorSheet)
#endif
                    }
                } else {
                    DeviceListMainView()
                }
            }
            .environment(router)
            .environment(sonosService)
            .environment(subscriptionService)
            .environment(alertService)
            .onOpenURL(perform: handle)
            .withSheetDestinations(sheetDestinations: $router.presentedSheet)
            .task {
                subscriptionService.monitorChanges()
            }
            .onAppear {
                SonosService.shared.groupsChanged = { groups in
                    guard subscriptionService.subscription.isActive else { return }
                    liveActivityManager.createActivity()
                }

                SubscriptionService.shared.subscriptionUpdated = { subscription in
                    activeSubscription = subscription.isActive
#if canImport(WidgetKit)
                    WidgetCenter.shared.reloadAllTimelines()
#endif
                }
            }
            .onAppear { hideTitleBarOnCatalyst() }
#if targetEnvironment(macCatalyst)
            .frame(minWidth: 500, minHeight: 500)
#endif
        }
        .windowResizability(.contentMinSize)
        .onChange(of: scenePhase) {
            handleScenePhase(scenePhase)
        }
        .onChange(of: subscriptionService.subscription, initial: true) { oldValue, newValue in
            activeSubscription =  newValue.isActive
        }
        .onChange(of: selectedID) { old, new in
            if let id = selectedID, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                if let sheet = router.inspectorSheet, sheet.id == "search" {
                    router.inspectorSheet = .search(group: sonosService.sorted[group], instant: false)
                } else if let sheet = router.inspectorSheet, sheet.id == "queue" {
                    router.inspectorSheet = .queue(group: $sonosService.sorted[group])
                }
            }
        }
        .commands {
            SidebarCommands()
            InspectorCommands()
        }
    }

    func hideTitleBarOnCatalyst() {
#if targetEnvironment(macCatalyst)
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.titlebar?.titleVisibility = .hidden
#endif
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
                await liveActivityManager.refresh(type: .refresh)
            }

            Task {
                try? await subscriptionService.checkSubscription()
            }

            Task {
                try? await Task.sleep(for: .seconds(1))
                ReviewService.shared.askForRatingIfNeeded()
            }
        case .inactive:
            print("Inactive")
#if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
#endif
            Task {
                await liveActivityManager.refresh(type: .refresh)
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
        Task { @MainActor in
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
            if components.host?.lowercased() == "subscribe" {
                router.presentedSheet = .paywall
                return
            }

            if components.host?.lowercased() == "search", let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
                router.presentedSheet = nil

                if let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) {
                    if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                        router.path.removeAll()
                        router.navigate(to: .player(groupID: group.coordinatorID))
                    } else if router.path.isEmpty {
                        router.navigate(to: .player(groupID: group.coordinatorID))
                    }
                    router.presentedSheet = .search(group: group)
                    return
                }
                Task {
                    try await sonosService.fetch(useCache: true)
                    if let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) {
                        if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                            router.path.removeAll()
                            router.navigate(to: .player(groupID: group.coordinatorID))
                        } else if router.path.isEmpty {
                            router.navigate(to: .player(groupID: group.coordinatorID))
                        }
                        router.presentedSheet = .search(group: group)
                        return
                    }
                }
            }

            if components.host?.lowercased() == "device", let id = components.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty {
                router.presentedSheet = nil

                if let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) {
                    if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                        router.path.removeAll()
                        router.navigate(to: .player(groupID: group.coordinatorID))
                    } else if router.path.isEmpty {
                        router.navigate(to: .player(groupID: group.coordinatorID))
                    }
                    return
                }
                Task {
                    try await sonosService.fetch(useCache: true)
                    if let group = sonosService.groups.first(where:  { $0.coordinatorRoom.id == id} ) {
                        if let currentPath = router.path.last, currentPath != .player(groupID: group.coordinatorID) {
                            router.path.removeAll()
                            router.navigate(to: .player(groupID: group.coordinatorID))
                        } else if router.path.isEmpty {
                            router.navigate(to: .player(groupID: group.coordinatorID))
                        }
                        return
                    }
                }
            }

            if components.host?.lowercased() == "scene", let name = components.queryItems?.first(where: { $0.name == "name" })?.value, !name.isEmpty {
                guard let scene = scenes.first(where: { $0.name == name }) else { return }
                Task {
                    alertService.showAlert(with: "Running \(scene.name)")
                    try await sonosService.runScene(scene)
                }
            }

            if components.host?.lowercased() == "play", let paths = components.string?.split(separator: "/").map(String.init) {
                if paths.count < 3 {
                    return
                }
                guard let service = MusicService(service: paths[2]),
                      let type = ContentType(paths[3])
                else { return }

                let id = paths[4]

                let media = MediaContent(service: service, id: id, type: type, location: nil)
                print(media)
                router.sheet(to: .playMedia(content: media))
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {

        guard let windowScene = (scene as? UIWindowScene) else { return }

#if targetEnvironment(macCatalyst)
        if let titlebar = windowScene.titlebar {
            titlebar.titleVisibility = .hidden
            titlebar.toolbar = nil
        }
#endif

    }
}
