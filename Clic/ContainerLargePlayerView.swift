import SwiftUI
import SonosKit
import VibesDS

struct ContainerLargePlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var id: String?
    @State var refreshID = UUID()

    var body: some View {
        @Bindable var sonosService = sonosService
        @Bindable var router = router

        Group {
            if let id, let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                LargePlayerView(group: $sonosService.sorted[group])
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .vision {
                    Button {
                        if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                            router.popover = .groupScreen(group: sonosService.sorted[group])
                        }
                    } label: {
                        GroupIconView()
                            .tint(.primary)
                    }
                    .withPopoverDestinations(popoverDestination: $router.popover)
                    .id(refreshID)
                    
                    Button {
                        if let groupID = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                            router.volumePopover = .volumeControlsScreen(groupID: sonosService.sorted[groupID].coordinatorID)
                        }
                    } label: {
                        Label("Room Volume", systemImage: "speaker.wave.2.fill")
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .fontDesign(.rounded)
                            .tint(.primary)
                    }
                    .withPopoverDestinations(popoverDestination: $router.volumePopover)
                    .tint(.primary)

                    Button {
                        if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                            if router.inspectorSheet != .search(group: sonosService.sorted[group]) {
                                router.inspectorSheet = .search(group: sonosService.sorted[group])
                            } else {
                                router.inspectorSheet = nil
                            }
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .tint(.primary)
                    }
                    .id(refreshID)

                    Button {
                        if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                            if router.inspectorSheet != .browse(group: sonosService.sorted[group]) {
                                router.inspectorSheet = .browse(group: sonosService.sorted[group])
                            } else {
                                router.inspectorSheet = nil
                            }
                        }
                    } label: {
                        Image(systemName: "music.note.house.fill")
                            .tint(.primary)
                    }
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
                        if let id, let groupID = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                            QueueIconView(group: $sonosService.sorted[groupID])
                                .tint(.primary)
                        }
                    }
                    .id(refreshID)
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
