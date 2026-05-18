import SwiftUI
import SonosKit
import VibesDS

struct ContainerLargePlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State var refreshID = UUID()
    
    var body: some View {
        VStack {
            if let id = router.selectedID, sonosService.groups.contains(where: { $0.coordinatorID == id }) {
                LargePlayerView(coordinatorID: id)
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .vision, horizontalSizeClass != .compact {
                                Button {
                                    if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                                        if router.inspectorSheet != .search(group: sonosService.sorted[group]) {
                                            router.inspectorSheet = .search(group: sonosService.sorted[group])
                                        } else {
                                            router.inspectorSheet = nil
                                        }
                                    }
                                } label: {
                                    Label("Search", systemImage: "magnifyingglass")
                                }
                                .id(refreshID)
                                .help("Search")
                                .tint(router.inspectorSheet?.id == "search" ? .accentColor : .primary)
                                
                                Button {
                                    if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                                        if router.inspectorSheet != .browse(group: sonosService.sorted[group]) {
                                            router.inspectorSheet = .browse(group: sonosService.sorted[group])
                                        } else {
                                            router.inspectorSheet = nil
                                        }
                                    }
                                } label: {
                                    Label("Browse", image: "home.fill")
                                }
                                .id(refreshID)
                                .help("Browse")
                                .tint(router.inspectorSheet?.id == "browse" ? .accentColor : .primary)
                                
                                Button {
                                    if let group = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                                        if router.inspectorSheet != .queue(group: sonosService.sorted[group]) {
                                            router.inspectorSheet = .queue(group: sonosService.sorted[group])
                                        } else {
                                            router.inspectorSheet = nil
                                        }
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
