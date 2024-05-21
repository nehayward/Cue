import SwiftUI
import SonosKit

struct ContainerLargePlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var id: String?
    @State var refreshID = UUID()

    var body: some View {
        Group {
            @Bindable var sonosService = sonosService
            @Bindable var router = router

            if let id, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                LargePlayerView(group: $sonosService.sorted[group])
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .vision {
                                Button {
                                    if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                                        router.popover = .groupScreen(group: sonosService.sorted[group])
                                    }
                                } label: {
                                    Image(systemName: "hifispeaker")
                                }
                                .withPopoverDestinations(popoverDestination: $router.popover)
                                .tint(.primary)
                                .id(refreshID)
                                
                                Button {
                                    if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                                        if router.inspectorSheet != .search(group: sonosService.sorted[group]) {
                                            router.inspectorSheet = .search(group: sonosService.sorted[group])
                                        } else {
                                            router.inspectorSheet = nil
                                        }
                                    }
                                } label: {
                                    Image(systemName: "sparkle.magnifyingglass")
                                }
                                .tint(.primary)
                                .id(refreshID)


                                Button {
                                    if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                                        if router.inspectorSheet != .queue(group: $sonosService.sorted[group]) {
                                            router.inspectorSheet = .queue(group: $sonosService.sorted[group])
                                        } else {
                                            router.inspectorSheet = nil
                                        }
                                    }
                                } label: {
                                    Image(systemName: "list.bullet")
                                }
                                .tint(.primary)
                                .id(refreshID)
                            }
                        }
                    }
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: scenePhase) {
            if horizontalSizeClass != .compact, UIDevice.current.userInterfaceIdiom == .pad {
                refreshID = UUID()
            }
        }
    }
}
