import Analytics
import RevenueCatUI
import SubscriptionKit
import SonosKit
import VibesDS
import MusicSearchKit
import SwiftUI

@MainActor
extension View {
    
    func withSheetDestinations(sheetDestinations: Binding<SheetDestination?>) -> some View {
        sheet(item: sheetDestinations) { destination in
            Group {
                switch destination {
                case let .groupScreen(group):
                    GroupScreen(coordinatorID: group.coordinatorID, sheetDestination: sheetDestinations)
                case .paywall:
                   ClicPaywall()
//                    PaywallView(displayCloseButton: true)
//                        .onPurchaseCompleted { transaction, customerInfo in
//                                ///                     print("Purchase completed: \(customerInfo.entitlements)")
//                                ///                     self.displayPaywall = false
//                                ///                 }
//                            ///                 print(
//                            print("Complete")
//                        }
//                        .onAppear {
//                            Analytics.shared.track(.viewedPaywall)
//                        }
                case .settings:
                    PreferenceScreen()
                case let .search(group):
                    SearchScreen(group: group)
                        .environment(Router())
                    // MARK: Add back later maybe
//                        .environment(Router.search)
                case let .sceneSearchAdd(adding):
                    SearchScreen()
                        .environment(Router())
                        .environment(adding)
                case let .queue(group):
                    QueueScreen(group: group)
                        .presentationDetents([.medium, .large])
                case let .playContent(content):
                    PlayerSelectionView(playableContent: content)
                case let .playMedia(content):
                    NavigationStack {
                        PlayerSelectionView(mediaContent: content)
                            .navigationBarTitleDisplayMode(.inline)
                            .navigationTitle("Choose Group")
                    }
                case let .createScene(content):
                    NavigationStack {
                        SceneBuilderScreen(sheetDestination: .constant(nil), playableContent: content)
                    }
                case .scenes:
                    SceneView()
                case let .mediaDetail(content, group):
                    NavigationStack {
                        MediaDetailView(playableContent: content, group: group)
                            .environment(Router())
                            .navigationBarTitleDisplayMode(.inline)
                            .addDismiss {
                                sheetDestinations.wrappedValue = nil
                            }
                    }
                    .scrollContentBackground(.hidden)
                    .presentationBackground(.thinMaterial)
                case let .artistDetail(content, group):
                    Group {
                        @State var router = Router()
                        NavigationStack {
                            ArtistDetailView(playableContent: content, group: group)
                                .navigationBarTitleDisplayMode(.inline)
                                .withAppRouter(router: router)
                                .addDismiss {
                                    sheetDestinations.wrappedValue = nil
                                }
                        }
                        .environment(router)
                        .scrollContentBackground(.hidden)
                        .presentationBackground(.thinMaterial)
                    }
                case let .searchAdd(adding):
                    SearchScreen()
                        .environment(Router())
                        .environment(adding)
                case let .alarms(group):
                    Group {
                        @State var router = Router()
                        NavigationStack {
                            AlarmListView(group: group)
                                .withAppRouter(router: router)
                        }
                    }
                }
            }
            .withEnvironments()
        }
    }

    func withPopoverDestinations(popoverDestination: Binding<SheetDestination?>)  -> some View {
        popover(item: popoverDestination) { destination in
            Group {
                switch destination {
                case let .groupScreen(group):
                    GroupScreen(coordinatorID: group.coordinatorID, sheetDestination: popoverDestination)
                        .frame(idealWidth: 400, idealHeight: 800)
                case .paywall:
                    ClicPaywall()
                case .settings:
                    PreferenceScreen()
                case let .search(group):
                    SearchScreen(group: group)
                        .environment(Router())
                case let .sceneSearchAdd(adding):
                    SearchScreen()
                        .environment(Router())
                        .environment(adding)
                case let .queue(group):
                    QueueScreen(group: group)
                        .presentationDetents([.medium, .large])
                case let .playContent(content):
                    PlayerSelectionView(playableContent: content)
                case let .playMedia(content):
                    NavigationStack {
                        PlayerSelectionView(mediaContent: content)
                            .navigationBarTitleDisplayMode(.inline)
                            .navigationTitle("Choose Group")
                    }
                case let .createScene(content):
                    NavigationStack {
                        SceneBuilderScreen(sheetDestination: .constant(nil), playableContent: content)
                    }
                case .scenes:
                    SceneView()
                case let .mediaDetail(content, group):
                    NavigationStack {
                        MediaDetailView(playableContent: content, group: group)
                            .environment(Router())
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .scrollContentBackground(.hidden)
                    .presentationBackground(.thinMaterial)
                case let .artistDetail(content, group):
                    @State var router = Router()
                    NavigationStack(path: $router.path) {
                        ArtistDetailView(playableContent: content, group: group)
                            .navigationBarTitleDisplayMode(.inline)
                            .withAppRouter(router: router)
                            .environment(router)
                    }
                    .scrollContentBackground(.hidden)
                    .presentationBackground(.thinMaterial)
                case let .searchAdd(adding):
                    SearchScreen()
                        .environment(adding)
                        .environment(Router())
                case .alarms:
                    NavigationStack {
                        AlarmListView()
                    }
                }
            }
            .withEnvironments()
        }
    }

    func withAppRouter(router: Router) -> some View {
        @Bindable var sonosService = SonosService.shared

        return navigationDestination(for: RouterDestination.self) { destination in
            switch destination {
            case let .player(groupID):
                if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == groupID }) {
                    LargePlayerView(group: $sonosService.sorted[group])
                } else {
                    Text("Group No Longer Available")
                        .onTapGesture {
                            router.path.removeAll()
                        }
                }
            case let .groupDestination(content, position):
                PlayerSelectionView(playableContent: content, position: position)
            case .manageScenes:
                ManageSceneScreen()
            case let .mediaDetail(content, group):
                MediaDetailView(playableContent: content, group: group)
            case let .artistDetail(content, group):
                ArtistDetailView(playableContent: content, group: group)
            case let .createScene(content):
                SceneBuilderScreen(sheetDestination: .constant(nil), playableContent: content)
            case .alarms:
                AlarmListView()
            case let .addAlarm(group):
                AlarmView(group: group, alarm: .newAlarm)
            case let .editAlarm(alarm):
                AlarmView(edit: true, alarm: alarm)
            }
        }
    }

    func withInspector(inspectorDestination: Binding<SheetDestination?>) -> some View {
        #if !os(visionOS)
        inspector(isPresented: .constant(inspectorDestination.wrappedValue  != nil)) {
            Group {
                switch inspectorDestination.wrappedValue {
                case let .search(group):
                    SearchScreen(group: group)
                        .inspectorColumnWidth(400)
                case let .queue(group):
                    QueueScreen(group: group)
                        .inspectorColumnWidth(400)
                default:
                    EmptyView()
                        .onAppear {
                            inspectorDestination.wrappedValue = nil
                        }
                }
            }
            .withEnvironments()
        }
        #else
        return self
        #endif
    }

    func withEnvironments() -> some View {
        environment(SonosService.shared)
            .environment(SubscriptionService.shared)
            .environment(AlertService.shared)
            .environment(MusicSearchService.shared)
    }

    @ViewBuilder
    func addDismiss(action: @escaping () -> Void) -> some View {
        if [.mac, .vision, .pad].contains(UIDevice.current.userInterfaceIdiom) {
            toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", systemImage: "xmark.circle.fill", role: .cancel, action: action)
                        .labelStyle(.iconOnly)
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
        } else {
            self
        }
    }
}
