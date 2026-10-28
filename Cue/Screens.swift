//
//  Screens.swift
//  Cue
//
//  Created by Nick Hayward on 8/25/26.
//
import Defaults
import MusicSearchKit
import SwiftUI

@MainActor
enum Screens {

    /// Each tab's own `SelectedGroupService`, made once. Made here in the
    /// builder, a new one went into the environment every time `CueApp`'s
    /// body ran — any UserDefaults write runs it, for its `@AppStorage` —
    /// and every row reading it redrew: on an iPhone, Radio's rows about a
    /// thousand times a second, which kept its list from scrolling.
    private static var groupServices: [String: SelectedGroupService] = [:]

    private static func groupService(_ tab: String) -> SelectedGroupService {
        if let service = groupServices[tab] { return service }
        let service = SelectedGroupService(group: nil)
        groupServices[tab] = service
        return service
    }

    @ViewBuilder
    static var home: some View {
        let selectedGroupService = groupService("home")

        HomeScreen()
            .tint(Color("Accent"))
            .environment(selectedGroupService)
    }
    
    @ViewBuilder
    static var search: some View {
        let searchRouter = Router.search
        let selectedGroupService = groupService("search")
        SearchScreen(favorites: true, isTab: true)
            // The TabView is tinted `.primary` so its sidebar selection reads
            // that way; tab content wants the app's real accent back.
            .tint(Color("Accent"))
            .environment(searchRouter)
            .environment(selectedGroupService)
            .onDisappear {
                Router.search.path.removeAll()
                Router.search.presentedSheet = nil
            }
    }
    
    @ViewBuilder
    static var browse: some View {
        let selectedGroupService = groupService("browse")
        
        BrowseScreen()
            .tint(Color("Accent"))
            .environment(selectedGroupService)
        
    }

    /// The Radio tab: stations from every source, and a search over them.
    @ViewBuilder
    static var radio: some View {
        let selectedGroupService = groupService("radio")

        RadioScreen()
            .tint(Color("Accent"))
            .environment(selectedGroupService)
    }

    /// The Audiobooks tab: the book listened to last, and every book.
    @ViewBuilder
    static var audiobooks: some View {
        let selectedGroupService = groupService("audiobooks")

        AudiobooksScreen()
            .tint(Color("Accent"))
            .environment(selectedGroupService)
    }

    /// The Downloads tab: the music on this device, and what's coming down.
    @ViewBuilder
    static var downloads: some View {
        let selectedGroupService = groupService("downloads")

        DownloadsTabScreen()
            .tint(Color("Accent"))
            .environment(selectedGroupService)
    }

    /// A provider's own tab — its library's front page, listing the
    /// collections its sidebar section is showing.
    @ViewBuilder
    static func providerRoot(_ service: MediaSearchService, collections: [ProviderCollection]) -> some View {
        let selectedGroupService = groupService("provider|\(service.rawValue)")

        ProviderTabScreen(service: service, collections: collections)
            .tint(Color("Accent"))
            .environment(selectedGroupService)
    }

    /// One collection of a provider — a tab in its sidebar section.
    @ViewBuilder
    static func providerCollection(_ service: MediaSearchService, collections: [ProviderCollection], collection: ProviderCollection) -> some View {
        let selectedGroupService = groupService("provider|\(service.rawValue)|\(collection.rawValue)")

        ProviderTabScreen(service: service, collections: collections, collection: collection)
            .tint(Color("Accent"))
            .environment(selectedGroupService)
    }
}

/// The Next Up panel, beside the whole `TabView`. Inside a tab it stopped
/// above the tab bar accessory, whose inset the tab's content area ends at;
/// out here it runs the window's full height, and the tab bar and the mini
/// player centre on the content column beside it. On the Mac the sidebar
/// is inside the `TabView`, so it sits at the leading edge and the panel
/// at the trailing one.
///
/// Hidden at compact widths rather than a sheet: on iPhone the queue is the
/// player's, and a sheet here would fight the one it presents (they share
/// the stored flag).
struct WindowQueuePanel: ViewModifier {
    @AppStorage(AppStorageKeys.queueInspectorVisible) private var showQueue: Bool = false

    func body(content: Content) -> some View {
        content.queuePanel(isPresented: $showQueue, compact: .hidden) { QueueNextUpView() }
    }
}

