//
//  Ornament.swift
//  Cue
//
//  Created by Nick Hayward on 8/28/25.
//
import SonosKit
import SwiftUI

/// The inspector destinations capture the group at open time; the ornament
/// tracks the *selected* group, so resolve it live with the capture as
/// fallback.
@MainActor
private func liveGroup(router: Router, fallback: GroupRoom?) -> GroupRoom? {
    if let id = router.selectedID,
       let live = SonosService.shared.sorted.first(where: { $0.coordinatorID == id }) {
        return live
    }
    return fallback
}

extension View {
    func visionOrnament(router: Router) -> some View {
#if os(visionOS)
        ornament(visibility: .visible, attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
            VStack {
                switch router.inspectorSheet {
                case let .search(group):
                    // Router.search, matching the sheet registry — otherwise
                    // SearchScreen inherits Router.main and attaches a second
                    // sheet host to Router.main.presentedSheet alongside the
                    // app-level one.
                    SearchScreen {
                        router.inspectorSheet = nil
                    }
                    .environment(Router.search)
                    .environment(SelectedGroupService(group: liveGroup(router: router, fallback: group)))
                    .onDisappear {
                        Router.search.path.removeAll()
                        Router.search.presentedSheet = nil
                    }
                case let .queue(group):
                    // Track the selected group live and remount per group —
                    // QueueScreen's loading is appear-driven, so a param-only
                    // group change leaves the previous queue on screen.
                    let current = liveGroup(router: router, fallback: group) ?? group
                    QueueScreen(group: current) {
                        router.inspectorSheet = nil
                    }
                    .id(current.coordinatorID)
                case let .browse(group):
                    BrowseScreen {
                        router.inspectorSheet = nil
                    }
                    .environment(SelectedGroupService(group: liveGroup(router: router, fallback: group)))
                default:
                    // No onAppear-nil: a late-firing onAppear from this
                    // branch can write nil over a freshly-set destination.
                    EmptyView()
                }
            }
            .glassBackgroundEffect()
            .frame(minWidth: 400, minHeight: 800)
            .offset(x: router.inspectorSheet != nil ? 0 : -400)
            .offset(z: router.inspectorSheet != nil ? 0 : -64)
            .opacity(router.inspectorSheet != nil ? 1 : 0)
            .animation(.spring, value: router.inspectorSheet)
            .withEnvironments()
        }
#else
        self
#endif
    }
}
