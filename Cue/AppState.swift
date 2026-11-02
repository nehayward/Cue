import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI
import UIKit

/// The app's own state as its scene draws it: the settings it reads from
/// UserDefaults, and the tabs those, the services and what's downloaded
/// make.
///
/// Observed, rather than `@AppStorage` in `CueApp`: a view holding
/// `@AppStorage` runs again on every UserDefaults write, of any key, iOS's
/// own as Cue comes back included, and `CueApp` running again handed the
/// tab bar its tabs again each time (`SameTabsFilter`), and redrew the mini
/// player and every tab's queue panel with it. This is the one place the
/// settings are read and written: the settings screens bind to it, and
/// each is saved to UserDefaults when it changes, so nothing here runs on
/// another key's write.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    // MARK: - Settings

    /// Settings ▸ Appearance ▸ Radio.
    var showRadioTab: Bool {
        didSet { save(showRadioTab, from: oldValue, as: AppStorageKeys.showRadioTab) }
    }
    /// Settings ▸ Appearance ▸ Audiobooks.
    var showAudiobooksTab: Bool {
        didSet { save(showAudiobooksTab, from: oldValue, as: AppStorageKeys.showAudiobooksTab) }
    }
    /// Settings ▸ Appearance ▸ Downloads: whether the tab shows while there's
    /// a network. Offline it shows whatever this says.
    var showDownloadsTab: Bool {
        didSet { save(showDownloadsTab, from: oldValue, as: AppStorageKeys.showDownloadsTab) }
    }
    /// Settings ▸ Appearance ▸ Theme, applied to the windows.
    var colorScheme: ColorSchemePreference {
        didSet { save(colorScheme.rawValue, from: oldValue.rawValue, as: AppStorageKeys.colorScheme) }
    }
    #if DEBUG
    /// Settings ▸ Debug ▸ Shrink Tab Bar on Scroll.
    var minimizesTabBar: Bool {
        didSet { save(minimizesTabBar, from: oldValue, as: Self.minimizesTabBarKey) }
    }
    private static let minimizesTabBarKey = "dance.cue.debug.minimizeTabBar"
    #endif

    /// The queue panel beside the content, on iPad and the Mac
    /// (`AppStorageKeys.queueInspectorVisible`): the window's panel, the
    /// player's, the mini player's button, and the Mac's toolbar item and
    /// View menu command all show and flip this one flag.
    var showsQueuePanel: Bool {
        didSet { save(showsQueuePanel, from: oldValue, as: AppStorageKeys.queueInspectorVisible) }
    }

    /// The queue panel's width, which every panel shares (the window's,
    /// each tab's on a phone, the player's), set by dragging its divider:
    /// written once as the drag ends.
    var queuePanelWidth: Double {
        didSet { save(queuePanelWidth, from: oldValue, as: AppStorageKeys.queuePanelWidth) }
    }

    /// The sidebar's edits: which provider tabs show, and the order of their
    /// sections. Only with the library sections (`showsLibrarySections`),
    /// off for now, so it has never been written; kept as JSON.
    var tabCustomization: TabViewCustomization {
        didSet {
            guard tabCustomization != oldValue else { return }
            UserDefaults.standard.set(try? JSONEncoder().encode(tabCustomization), forKey: AppStorageKeys.tabViewCustomization)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        showRadioTab = Self.bool(AppStorageKeys.showRadioTab, default: true)
        showAudiobooksTab = Self.bool(AppStorageKeys.showAudiobooksTab, default: true)
        showDownloadsTab = Self.bool(AppStorageKeys.showDownloadsTab, default: true)
        colorScheme = Self.colorSchemeSetting()
        #if DEBUG
        minimizesTabBar = Self.bool(Self.minimizesTabBarKey, default: true)
        #endif
        showsQueuePanel = defaults.bool(forKey: AppStorageKeys.queueInspectorVisible)
        queuePanelWidth = defaults.object(forKey: AppStorageKeys.queuePanelWidth) as? Double ?? 320
        tabCustomization = defaults.data(forKey: AppStorageKeys.tabViewCustomization)
            .flatMap { try? JSONDecoder().decode(TabViewCustomization.self, from: $0) } ?? TabViewCustomization()
    }

    /// A setting written to UserDefaults when it changed: a write of any key
    /// runs every view still holding `@AppStorage` again.
    private func save<Value: Equatable>(_ value: Value, from oldValue: Value, as key: String) {
        guard value != oldValue else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    private static func colorSchemeSetting() -> ColorSchemePreference {
        UserDefaults.standard.string(forKey: AppStorageKeys.colorScheme).flatMap(ColorSchemePreference.init(rawValue:)) ?? .system
    }

    // MARK: - Tabs

    private var coreFeatures: CoreFeatures { .shared }
    private var offline: OfflineMode { .shared }

    /// Home, the provider sections and the sidebar's Edit — off everywhere
    /// for now. Every device has the phone's three tabs, Browse, Search and
    /// Radio, with providers reached from Browse's menu; the Mac shows them
    /// in its sidebar (`AdaptiveTabViewStyle`), iPhone and iPad in the tab
    /// bar. The adaptable sidebar's rebuild on an iPad resize (a
    /// size-class change folds the sidebar's tabs into a tab bar) was also
    /// crashing UIKit with a nil tab bar item. Kept as a switch for when
    /// the sections come back.
    var showsLibrarySections: Bool { false }

    /// The providers with a section in the sidebar: every one that browses
    /// by collection and is switched on in Services, in the order the app
    /// lists services. Nothing is added or removed by hand any more — a
    /// provider comes with being switched on, and which of its tabs show is
    /// the sidebar's edit mode's to decide.
    var tabProviders: [MediaSearchService] {
        MediaSearchService.supported.filter { $0.canBeTab && coreFeatures.isEnabled($0) }
    }

    /// The collections a provider's own tab lists on its front page: the
    /// ones its sidebar section is showing. Read from the customization —
    /// a tab the user hid there is left off, one they showed is added — with
    /// `defaultTabCollections` standing in where they haven't decided.
    func shownCollections(of service: MediaSearchService) -> [ProviderCollection] {
        let defaults = service.defaultTabCollections
        return service.tabCollections.filter { collection in
            switch tabCustomization[tab: service.tabCustomizationID(for: collection)].sidebarVisibility {
            case .visible: true
            case .hidden: false
            case .automatic: defaults.contains(collection)
            @unknown default: defaults.contains(collection)
            }
        }
    }

    /// Whether the Radio tab has a source to draw on: TuneIn or Apple Music
    /// switched on in Services. Those are the two whose stations play on
    /// this device as well as on a speaker, which is the tab's rule — Sonos
    /// Radio and Sonos favorites are speaker-only and stay on Browse and
    /// Search. The user can hide it in Settings › Appearance, and it goes
    /// on its own while offline: every station streams, so
    /// there is nothing there to play.
    var showsRadioTab: Bool {
        showRadioTab
            && !offline.isActive
            && [MediaSearchService.tuneIn, .apple].contains { coreFeatures.isEnabled($0) }
    }

    /// Whether the Audiobooks tab shows: always, unless it's hidden in
    /// Settings › Appearance. With no server for books yet it asks to sign
    /// in to Plex or Audiobookshelf (`AudiobooksScreen`), so books are
    /// there to find before any server is set up. While offline only books
    /// downloaded whole can play, and nothing can be signed in to, so it
    /// stays only while there are some.
    var showsAudiobooksTab: Bool {
        guard showAudiobooksTab else { return false }
        guard offline.isActive else { return true }
        // The Files folder's books are on this device, offline or not.
        return AudiobookDownloads.hasDownloadedBooks
            || (coreFeatures.isEnabled(.files) && !FilesLibraryService.shared.books.isEmpty)
    }

    /// Whether the Downloads tab shows: always offline, in Browse's place
    /// (what's here is all there is to play); otherwise while it's switched
    /// on in Settings › Appearance and has something to show, songs or
    /// books Cue downloaded or is downloading, or Apple Music songs the
    /// Music app keeps downloaded. Read through the download manager's
    /// summary, which moves as songs land rather than with every byte of
    /// progress, so the tab bar isn't redrawn while they come down.
    var showsDownloadsTab: Bool {
        if offline.isActive { return true }
        return showDownloadsTab
            && (DownloadManager.shared.musicSummary.hasDownloads
                || (coreFeatures.isEnabled(.apple) && !AppleDownloadsIndex.shared.songs.isEmpty))
    }

    /// Whether Browse shows: not offline, where its providers have nothing
    /// to show and Downloads takes its place.
    var showsBrowseTab: Bool {
        !offline.isActive
    }

    /// The tab the selection falls back to: Home where the sidebar has
    /// one, Browse on the tab bar, which has none, and Downloads offline,
    /// in Browse's place.
    var fallbackTab: AppTab {
        if offline.isActive, !showsLibrarySections { return .downloads }
        return showsLibrarySections ? .home : .browse
    }

    /// Every tab the view builds right now. The selection is checked
    /// against this before the `TabView` sees it: a selection naming a tab
    /// that isn't there — a provider switched off in Services, a collection
    /// tab hidden in the sidebar's Edit while it was showing, Home's "Open"
    /// on a provider that's out — is what UIKit's tab bar asserts on ("No
    /// view controller matches the UITabBarItem"), and it asserts during
    /// layout, before any `onChange` gets a chance to move the selection.
    var availableTabs: Set<AppTab> {
        var tabs: Set<AppTab> = [.search]
        if showsBrowseTab || showsLibrarySections {
            tabs.insert(.browse)
        }
        if showsRadioTab {
            tabs.insert(.radio)
        }
        if showsAudiobooksTab {
            tabs.insert(.audiobooks)
        }
        if showsDownloadsTab {
            tabs.insert(.downloads)
        }
        if showsLibrarySections {
            tabs.insert(.home)
            for service in tabProviders {
                tabs.insert(.provider(service))
                for collection in shownCollections(of: service) {
                    tabs.insert(.providerCollection(service, collection))
                }
            }
        }
        return tabs
    }

    /// The router's selection, or the fallback when it names a tab that
    /// isn't built.
    func resolvedTab(_ tab: AppTab) -> AppTab {
        availableTabs.contains(tab) ? tab : fallbackTab
    }

    /// The tab bar shrinks as a page scrolls down, the mini player moving
    /// into it.
    var tabBarMinimizes: Bool {
        #if DEBUG
        minimizesTabBar
        #else
        true
        #endif
    }

    /// The download symbol, or while songs or books come down a ring round
    /// the arrow filling with the run (`runProgressStep`, which moves in
    /// steps, so the tab bar isn't redrawn with every byte). A bare
    /// `Image`: the tab bar takes the image out of the label.
    var downloadsTabIcon: Image {
        let manager = DownloadManager.shared
        guard manager.musicSummary.remainingDownloads > 0 else {
            return Image(systemName: "arrow.down.circle")
        }
        return Image(uiImage: DownloadRingIcon.image(step: manager.runProgressStep))
    }

    /// The Downloads tab's badge: the songs and books still to come on iPad
    /// and the Mac, whose top bar draws titles only; none on the phone,
    /// where the ring says as much.
    var downloadsTabBadge: Int {
        UIDevice.current.userInterfaceIdiom == .phone ? 0 : DownloadManager.shared.musicSummary.remainingDownloads
    }
}

/// The Downloads tab's icon while songs or books come down: a ring that
/// fills with the run, round the download arrow. A template image, tinted
/// by the tab bar like a symbol, since the tab bar takes only a plain image
/// from a tab's label; one drawn a step and kept.
@MainActor
private enum DownloadRingIcon {
    private static var images: [Int: UIImage] = [:]

    static func image(step: Int) -> UIImage {
        if let image = images[step] { return image }
        let side: CGFloat = 25
        let lineWidth: CGFloat = 2
        let fraction = CGFloat(step) / CGFloat(DownloadManager.runProgressSteps)
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let ring = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: lineWidth / 2 + 0.5, dy: lineWidth / 2 + 0.5)
            let track = UIBezierPath(ovalIn: ring)
            track.lineWidth = lineWidth
            UIColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()
            if fraction > 0 {
                let arc = UIBezierPath(
                    arcCenter: CGPoint(x: side / 2, y: side / 2),
                    radius: ring.width / 2,
                    startAngle: -.pi / 2,
                    endAngle: -.pi / 2 + 2 * .pi * fraction,
                    clockwise: true
                )
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                UIColor.black.setStroke()
                arc.stroke()
            }
            if let arrow = UIImage(systemName: "arrow.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))?
                .withTintColor(.black, renderingMode: .alwaysOriginal) {
                let size = arrow.size
                arrow.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
            }
        }
        let image = drawn.withRenderingMode(.alwaysTemplate)
        images[step] = image
        return image
    }
}
