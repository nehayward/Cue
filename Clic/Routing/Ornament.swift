//
//  Ornament.swift
//  Clic
//
//  Created by Nick Hayward on 8/28/25.
//
import SwiftUI

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
                    .environment(SelectedGroupService(group: group))
                    .onDisappear {
                        Router.search.path.removeAll()
                        Router.search.presentedSheet = nil
                    }
                case let .queue(group):
                    QueueScreen(group: group) {
                        router.inspectorSheet = nil
                    }
                case let .browse(group):
                    let selectedGroupService = SelectedGroupService(group: group)
                    BrowseScreen {
                        router.inspectorSheet = nil
                    }
                    .environment(selectedGroupService)
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
            .withEnvironments()
        }
#else
        self
#endif
    }
}
