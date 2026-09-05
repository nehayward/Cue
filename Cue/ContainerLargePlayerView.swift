import SwiftUI
import SonosKit
import VibesDS
import Defaults

struct ContainerLargePlayerView: View {
    @AppStorage(AppStorageKeys.showArtworkOnly) private var showArtworkOnly: Bool = false
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State var refreshID = UUID()

    // When true this container shows the search/browse/queue toolbar and also
    // hosts the ellipsis menu on its trailing edge (LargePlayerView skips its
    // own copy so the menu doesn't lead the group).
    private var showsInspectorToolbar: Bool {
        (UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .vision) && horizontalSizeClass != .compact
    }

    var body: some View {
        VStack {
            if let id = router.selectedID, sonosService.groups.contains(where: { $0.coordinatorID == id }) {
                LargePlayerView(coordinatorID: id, showsEllipsisToolbarItem: !showsInspectorToolbar)
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            if showsInspectorToolbar {
                                Button {
                                    if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                                        router.toggleInspector(.search(group: sonosService.sorted[group]))
                                    }
                                } label: {
                                    Label("Search", systemImage: "magnifyingglass")
                                        .labelStyle(.iconOnly)
                                }
                                .id(refreshID)
                                .help("Search")
                                .tint(router.inspectorSheet?.id == "search" ? .accentColor : .primary)
                                
                                Button {
                                    if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                                        router.toggleInspector(.browse(group: sonosService.sorted[group]))
                                    }
                                } label: {
                                    Label("Browse", image: "home.fill")
                                        .labelStyle(.iconOnly)
                                }
                                .id(refreshID)
                                .help("Browse")
                                .tint(router.inspectorSheet?.id == "browse" ? .accentColor : .primary)
                                
                                Button {
                                    if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                                        router.toggleInspector(.queue(group: sonosService.sorted[group]))
                                    }
                                } label: {
                                    if let groupID = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
#if targetEnvironment(macCatalyst)
                                        Label {
                                            Text("Queue")
                                        } icon: {
                                            QueueIconView(group: sonosService.sorted[groupID])
                                                .tint(router.inspectorSheet?.id == "queue" ? .accentColor : .primary)
                                                .overlay(alignment: .topTrailing) {
                                                    if sonosService.sorted[groupID].playMode.contains(.shuffle) {
                                                        Image(systemName: "shuffle.circle.fill")
                                                            .symbolRenderingMode(.multicolor)
                                                            .foregroundStyle(.black.secondary)
                                                            .offset(x: 10, y: -10)
                                                    } else if sonosService.sorted[groupID].playMode.contains(.repeatAll) {
                                                        Image(systemName: "repeat.circle.fill")
                                                            .symbolRenderingMode(.multicolor)
                                                            .foregroundStyle(.black.secondary)
                                                            .offset(x: 10, y: -10)
                                                    } else if sonosService.sorted[groupID].playMode.contains(.repeatOne) {
                                                        Image(systemName: "repeat.1.circle.fill")
                                                            .symbolRenderingMode(.multicolor)
                                                            .foregroundStyle(.black.secondary)
                                                            .offset(x: 10, y: -10)
                                                    }
                                                }
                                        }
#else
                                        QueueIconView(group: sonosService.sorted[groupID])
                                            .tint(router.inspectorSheet?.id == "queue" ? .accentColor : .primary)
                                            .overlay(alignment: .topTrailing) {
                                                if sonosService.sorted[groupID].playMode.contains(.shuffle) {
                                                    Image(systemName: "shuffle.circle.fill")
                                                        .symbolRenderingMode(.multicolor)
                                                        .foregroundStyle(.black.secondary)
                                                        .offset(x: 10, y: -10)
                                                } else if sonosService.sorted[groupID].playMode.contains(.repeatAll) {
                                                    Image(systemName: "repeat.circle.fill")
                                                        .symbolRenderingMode(.multicolor)
                                                        .foregroundStyle(.black.secondary)
                                                        .offset(x: 10, y: -10)
                                                } else if sonosService.sorted[groupID].playMode.contains(.repeatOne) {
                                                    Image(systemName: "repeat.1.circle.fill")
                                                        .symbolRenderingMode(.multicolor)
                                                        .foregroundStyle(.black.secondary)
                                                        .offset(x: 10, y: -10)
                                                }
                                            }
#endif
                                    }
                                }
                                .id(refreshID)
                                .help("Queue")
                                .accessibilityLabel("Queue")
                                .accessibilityValue(
                                    sonosService.sorted.first { $0.coordinatorID == id }?.playMode.accessibilityDescription ?? ""
                                )
                                .accessibilityAddTraits(router.inspectorSheet?.id == "queue" ? .isSelected : [])

                                if let groupIndex = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                                    MenuInfoView(group: sonosService.sorted[groupIndex], showArtworkOnly: $showArtworkOnly)
                                        .tint(.primary)
                                        .id(refreshID)
                                }
                            }
                        }
                    }
            } else {
                ContentUnavailableView {
                    Label("Select a Speaker", systemImage: "hifispeaker.fill")
                } description: {
                    Text("Choose a speaker from the sidebar to see details and control playback.")
                }
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}
