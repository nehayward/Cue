import Analytics
import RevenueCatUI
import SubscriptionKit
import SonosKit
import VibesDS
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
                case let .search(group, instant):
                    NewSearchScreen(group: group, instant: instant)
                case let .add(mediaContent):
                    ImprovedSearch(adding: mediaContent, isAdding: true)
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
                case .createScene:
                    NavigationStack {
                        SceneBuilderScreen(sheetDestination: .constant(nil))
                            .addDismiss {
                                sheetDestinations.wrappedValue = nil
                            }
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
            case let .groupDestination(content):
                PlayerSelectionView(playableContent: content)
            case .manageScenes:
                ManageSceneScreen()
            case let .mediaDetail(content, group):
                MediaDetailView(playableContent: content, group: group)
            case let .artistDetail(content, group):
                ArtistDetailView(playableContent: content, group: group)
            }
        }
    }

    func withInspector(inspectorDestination: Binding<SheetDestination?>) -> some View {
        #if !os(visionOS)
        inspector(isPresented: .constant(inspectorDestination.wrappedValue  != nil)) {
            Group {
                switch inspectorDestination.wrappedValue {
                case let .search(group, instant):
                    NewSearchScreen(group: group, instant: instant)
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
    }

    func addDismiss(action: @escaping () -> Void) -> some View {
        #if targetEnvironment(macCatalyst) || os(visionOS)
            toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", systemImage: "xmark.circle.fill", role: .cancel, action: action)
                        .labelStyle(.iconOnly)
                }
            }
        #else
        return self
        #endif
    }
}
