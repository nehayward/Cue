#if targetEnvironment(macCatalyst)
import Defaults
import OSLog
import SonosKit
import SwiftUI
import UIKit

/// The panes of the Mac's Settings window, chosen from its toolbar. General
/// is Cue Super and Appearance's settings; About, Help, What's New and
/// Contact Support, the rest of the iPhone's Settings page, are in the menu
/// bar, where a Mac app keeps them.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, services, playback, sonos, storage

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .services: "Services"
        case .playback: "Playback"
        case .sonos: "Sonos"
        case .storage: "Storage"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .services: "music.note.list"
        case .playback: "play.circle"
        case .sonos: "hifispeaker"
        case .storage: "internaldrive"
        }
    }

    /// The toolbar's image. Sonos's carries the count of speakers found, cut out
    /// of a badge on its corner as Play On's speakers do.
    var image: UIImage? {
        self == .sonos ? Self.speakerImage(count: Self.speakerCount) : UIImage(systemName: symbol)
    }

    /// The active speakers found, none while they can't be reached.
    static var speakerCount: Int {
        let sonos = SonosService.shared
        return sonos.isAvailable ? sonos.sortedRooms.filter { $0.state == .active }.count : 0
    }

    /// A template, so the toolbar tints it as it does the others.
    static func speakerImage(count: Int) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 21)
        guard let speaker = UIImage(systemName: "hifispeaker", withConfiguration: configuration) else { return nil }
        guard count > 1 else { return speaker }

        let badgeHeight: CGFloat = 15
        let badgeWidth: CGFloat = count > 9 ? 21 : badgeHeight
        let size = CGSize(width: speaker.size.width + badgeWidth / 2, height: speaker.size.height + badgeHeight / 2)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            speaker.withTintColor(.black).draw(at: CGPoint(x: 0, y: size.height - speaker.size.height))
            let badge = CGRect(x: size.width - badgeWidth, y: 0, width: badgeWidth, height: badgeHeight)

            // A gap between the badge and the speaker.
            context.cgContext.setBlendMode(.clear)
            UIBezierPath(roundedRect: badge.insetBy(dx: -1.5, dy: -1.5), cornerRadius: badgeHeight).fill()
            context.cgContext.setBlendMode(.normal)
            UIColor.black.setFill()
            UIBezierPath(roundedRect: badge, cornerRadius: badgeHeight / 2).fill()

            // The count cut out of it.
            context.cgContext.setBlendMode(.clear)
            let text = NSAttributedString(string: "\(count)", attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .heavy),
                .foregroundColor: UIColor.black,
            ])
            let textSize = text.size()
            text.draw(at: CGPoint(x: badge.midX - textSize.width / 2, y: badge.midY - textSize.height / 2))
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    var itemIdentifier: NSToolbarItem.Identifier {
        .init("dance.cue.settings.\(rawValue)")
    }

    init?(itemIdentifier: NSToolbarItem.Identifier) {
        guard let pane = Self.allCases.first(where: { $0.itemIdentifier == itemIdentifier }) else { return nil }
        self = pane
    }

    /// The pane a page of Settings belongs to, and the page to open on it
    /// past the pane itself (Alarms, under Sonos). Anything else opens
    /// General, Appearance's settings included.
    static func place(of destination: RouterDestination) -> (pane: SettingsPane, page: RouterDestination?) {
        switch destination {
        case .servicePreferenceScreen: (.services, nil)
        case .settingsPage(.playback): (.playback, nil)
        case .settingsPage(.sonos): (.sonos, nil)
        case .settingsPage(.storage), .downloads: (.storage, nil)
        case .alarms: (.sonos, destination)
        default: (.general, nil)
        }
    }
}

/// Settings in a window of its own on the Mac, as a Mac app's are: Cue ▸
/// Settings… (⌘,), the sidebar's gear and every `.settings` sheet a router
/// is asked for (`Router.presentedSheet`) open it, or bring it forward where
/// it's open already. One window, its panes in a preference toolbar
/// (`SettingsToolbar`), titled for the pane on show; its width is fixed for
/// the window's scale (`InterfaceSize`) and its height fits the pane on show
/// (`fitHeight`), its top staying put, as a Mac app's settings window does.
/// Where it was left and the pane are kept for next time.
///
/// It's a SwiftUI scene of its own (`CueApp`), and `CueSceneDelegate` sets
/// it up rather than as the main window: a session is the Settings window's
/// when it connects just after `open()` asked for one, and is marked as such
/// in its `userInfo`, which macOS keeps with the session, so a window
/// brought back at launch is known too.
@MainActor @Observable
final class SettingsWindow {
    static let shared = SettingsWindow()
    static let sceneID = "settings"

    /// `log stream --predicate 'subsystem == "dance.cue" AND category == "settings"'`
    private static let log = Logger(subsystem: "dance.cue", category: "settings")
    private static let sessionMark = "dance.cue.window"

    private(set) var pane: SettingsPane
    /// A page to open on the pane once it shows (Alarms), taken by it.
    /// Never General's: nothing past it is opened from outside.
    var pendingPage: RouterDestination?

    /// SwiftUI's, from the main window (`LargeWindowShell`): the menu bar's
    /// command and the routers have no environment to read it from.
    @ObservationIgnored var openWindow: OpenWindowAction?
    @ObservationIgnored private weak var scene: UIWindowScene?
    @ObservationIgnored private var askedAt: Date?
    @ObservationIgnored private var frameObserver: WindowSizeObserver?
    @ObservationIgnored private let toolbarDelegate = SettingsToolbar()
    /// Each pane's height as last fitted, so the window opens at it.
    @ObservationIgnored private var fittedHeights: [SettingsPane: CGFloat] = [:]
    /// The count on the Sonos pane's icon.
    @ObservationIgnored private var shownSpeakerCount: Int?

    private init() {
        let saved = UserDefaults.standard.string(forKey: AppStorageKeys.settingsWindowPane)
        pane = saved.flatMap(SettingsPane.init(rawValue:)) ?? .general
    }

    // MARK: - Opening

    /// Shows Settings, on the pane `destination` belongs to when there's
    /// one, else where it was left.
    func open(_ destination: RouterDestination? = nil) {
        if let destination {
            let place = SettingsPane.place(of: destination)
            select(place.pane)
            pendingPage = place.page
        }
        if let scene {
            UIApplication.shared.requestSceneSessionActivation(scene.session, userActivity: nil, options: nil)
            return
        }
        guard let openWindow else {
            Self.log.error("no window to open Settings from")
            return
        }
        askedAt = .now
        openWindow(id: Self.sceneID)
    }

    func select(_ pane: SettingsPane) {
        guard pane != self.pane else { return }
        self.pane = pane
        pendingPage = nil
        scene?.title = pane.title
        scene?.titlebar?.toolbar?.selectedItemIdentifier = pane.itemIdentifier
        UserDefaults.standard.set(pane.rawValue, forKey: AppStorageKeys.settingsWindowPane)
    }

    // MARK: - The scene

    /// Whether `session` is this window's or another that isn't the main
    /// window (`PaywallWindow`), from its mark.
    static func isMarked(_ session: UISceneSession) -> Bool {
        session.userInfo?[sessionMark] as? Bool == true
    }

    static func markNotMain(_ session: UISceneSession) {
        var info = session.userInfo ?? [:]
        info[sessionMark] = true
        session.userInfo = info
    }

    /// Whether the session connecting is the Settings window's: marked, or
    /// asked for by `open()` a moment ago.
    func claims(_ session: UISceneSession) -> Bool {
        if Self.isMarked(session) { return true }
        guard let askedAt else { return false }
        return askedAt.timeIntervalSinceNow > -3
    }

    /// Sets the window up as it connects, in place of the main window's
    /// setup.
    func connect(_ scene: UIWindowScene) {
        askedAt = nil
        self.scene = scene
        Self.markNotMain(scene.session)

        if let titlebar = scene.titlebar {
            let toolbar = NSToolbar(identifier: "dance.cue.settings")
            toolbar.delegate = toolbarDelegate
            toolbar.displayMode = .iconAndLabel
            toolbar.allowsUserCustomization = false
            toolbar.selectedItemIdentifier = pane.itemIdentifier
            titlebar.toolbar = toolbar
            titlebar.toolbarStyle = .preference
            titlebar.titleVisibility = .visible
            titlebar.separatorStyle = .automatic
        }
        scene.title = pane.title
        scene.sizeRestrictions?.allowsFullScreen = false
        setFrame(scene, height: fittedHeights[pane] ?? (Self.height * Self.scale).rounded(), placing: true)
        frameObserver = WindowSizeObserver(windowScene: scene, store: .settings)
        followSpeakerCount()
        Self.log.info("Settings window connected on \(self.pane.rawValue, privacy: .public)")
    }

    func disconnect(_ scene: UIScene) {
        guard scene === self.scene else { return }
        self.scene = nil
        frameObserver = nil
    }

    /// Keeps the Sonos pane's icon on how many speakers are found, while the
    /// window's open.
    private func followSpeakerCount() {
        guard let scene else { return }
        let count = withObservationTracking {
            SettingsPane.speakerCount
        } onChange: {
            Task { @MainActor in
                SettingsWindow.shared.followSpeakerCount()
            }
        }
        guard count != shownSpeakerCount else { return }
        shownSpeakerCount = count
        let item = scene.titlebar?.toolbar?.items.first { $0.itemIdentifier == SettingsPane.sonos.itemIdentifier }
        item?.image = SettingsPane.speakerImage(count: count)
    }

    /// Fits the window's width to the window's scale when View ▸ Bigger or
    /// Smaller changes it; the pane's height follows from its list.
    func fitToScale() {
        guard let scene else { return }
        setFrame(scene, height: scene.effectiveGeometry.coordinateSpace.bounds.height, placing: false)
    }

    /// Fits the window's height to the list of the pane on show: as tall as
    /// its rows, within a floor and the screen, the list scrolling past
    /// that. Called whenever either height changes, so a row shown or
    /// hidden (a service switched on) resizes it too.
    func fitHeight(_ list: PaneListHeight, for pane: SettingsPane) {
        guard pane == self.pane, let scene else { return }
        let bounds = scene.effectiveGeometry.coordinateSpace.bounds
        guard bounds.height > 0, list.shown > 0 else { return }
        let scale = Self.scale
        let ceiling = min(Self.maximumHeight * scale, scene.screen.bounds.height * 0.85)
        let wanted = bounds.height + list.content - list.shown + Self.bottomMargin * scale
        let height = min(max(wanted, Self.minimumHeight * scale), ceiling).rounded()
        fittedHeights[pane] = height
        guard abs(height - bounds.height) >= 1 else { return }
        setFrame(scene, height: height, placing: false)
    }

    private static var scale: CGFloat {
        LargeWindowStyle.scale(AppState.shared.interfaceSize.typeSize)
    }

    /// Sizes the window: its width fixed, a Mac app's settings' way, at
    /// Cue's scale, and `height` (the iPad's points), neither left for the
    /// listener to drag. `placing` puts it where it was left, else over the
    /// main window; otherwise its top and centre stay where they are.
    private func setFrame(_ scene: UIWindowScene, height: CGFloat, placing: Bool) {
        let width = (Self.width * Self.scale).rounded()
        // A point either way, not one size: at 77% few sizes are a whole
        // number of the Mac's pixels, AppKit rounds the frame, and with the
        // least and most the same the frame never matched them, so UIKit
        // set it again from inside its own layout until AppKit gave up
        // (switching to Large crashed). Opened to anything first, so a
        // new least never passes the old most on the way.
        if let restrictions = scene.sizeRestrictions {
            restrictions.minimumSize = .zero
            restrictions.maximumSize = CGSize(width: width + 1, height: height + 1)
            restrictions.minimumSize = CGSize(width: width - 1, height: height - 1)
        }

        // The system's frame is in the Mac's points, the scene's in the
        // iPad's (macOS draws an iPad app at 77%), and holds the title bar
        // and toolbar too, which the change in height leaves as they are.
        let points = scene.effectiveGeometry.coordinateSpace.bounds.size
        let current = scene.effectiveGeometry.systemFrame
        let ratio = points.width > 0 && current.width > 0 ? current.width / points.width : 0.77
        var frame = current
        frame.size.width = width * ratio
        frame.size.height = current.height + (height - points.height) * ratio
        if placing {
            if let saved = WindowFrameStore.settings.savedFrame {
                frame.origin = saved.origin
            } else if let main = Self.mainWindowFrame(besides: scene) {
                frame.origin = CGPoint(x: main.midX - frame.width / 2, y: main.midY - frame.height / 2)
            }
        } else {
            frame.origin.x = current.midX - frame.width / 2
        }
        guard frame.size.width > 0, frame.size.height > 0 else { return }
        Self.log.info("Settings window \(String(describing: current), privacy: .public) → \(String(describing: frame), privacy: .public), \(height, privacy: .public) pt high")
        scene.requestGeometryUpdate(.Mac(systemFrame: frame)) { error in
            Self.log.error("Settings window frame: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func mainWindowFrame(besides settings: UIWindowScene) -> CGRect? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0 !== settings && !isMarked($0.session) }?
            .effectiveGeometry.systemFrame
    }

    /// In the iPad's points, at the default scale's 1: the width, the
    /// height before a pane has been measured, and the least and most a
    /// pane is fitted to.
    private static let width: CGFloat = 600
    private static let height: CGFloat = 520
    private static let minimumHeight: CGFloat = 240
    private static let maximumHeight: CGFloat = 780
    /// Room under a pane's last row, which a list has none of.
    private static let bottomMargin: CGFloat = 16
}

/// The list of the Settings window's pane on show: the height its rows take
/// (with its insets) and the height it's shown at.
struct PaneListHeight: Equatable {
    var content: CGFloat
    var shown: CGFloat
}

/// The Settings window's toolbar: a pane a button, the one on show selected,
/// as a Mac app's settings have them.
@MainActor
final class SettingsToolbar: NSObject, NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.itemIdentifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = SettingsPane(itemIdentifier: itemIdentifier) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.image = pane.image
        item.label = pane.title
        item.paletteLabel = pane.title
        item.target = self
        item.action = #selector(choose(_:))
        return item
    }

    @objc private func choose(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane(itemIdentifier: sender.itemIdentifier) else { return }
        SettingsWindow.shared.select(pane)
    }
}

/// What the Settings window shows: the pane chosen in its toolbar, each in a
/// navigation stack and router of its own for the pages further in, with no
/// bar of its own at the top (the window's title names it).
struct SettingsWindowScreen: View {
    @State private var settings = SettingsWindow.shared
    @State private var appState = AppState.shared

    var body: some View {
        SettingsPaneStack(pane: settings.pane)
            .id(settings.pane)
            .withEnvironments()
            .withPadLayout()
            .interfaceSize(appState.interfaceSize)
            .onChange(of: appState.interfaceSize) {
                settings.fitToScale()
            }
            .onAppear {
                appState.colorScheme.apply()
            }
            // Links go to the main window, which handles them, even while
            // this one is in front: it has no `onOpenURL`, and a link given
            // to it was lost.
            .handlesExternalEvents(preferring: [], allowing: [])
    }
}

private struct SettingsPaneStack: View {
    let pane: SettingsPane

    @State private var router = Router()
    @State private var settings = SettingsWindow.shared

    var body: some View {
        NavigationStack(path: $router.path) {
            root
                // The window fits the pane's own list; a page further in
                // scrolls in the height it has.
                .onScrollGeometryChange(for: PaneListHeight.self) { geometry in
                    PaneListHeight(
                        content: geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom,
                        shown: geometry.containerSize.height
                    )
                } action: { _, height in
                    settings.fitHeight(height, for: pane)
                }
                .toolbar(.hidden, for: .navigationBar)
                .withAppRouter()
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
        .withAlert()
        .onChange(of: settings.pendingPage, initial: true) { _, page in
            guard let page else { return }
            settings.pendingPage = nil
            router.path = [page]
        }
    }

    @ViewBuilder
    private var root: some View {
        switch pane {
        case .general: GeneralSettingsScreen()
        case .services: ServicePreferenceScreen()
        case .playback: PlaybackSettingsScreen()
        case .sonos: SonosSettingsScreen()
        case .storage: DownloadsScreen()
        }
    }
}

/// The Settings window's General pane: Cue Super, then how Cue looks
/// (Appearance's settings, which have no pane of their own on the Mac).
private struct GeneralSettingsScreen: View {
    var body: some View {
        Form {
            SuperSettingsSection()
            AppearanceSettingsSections()
#if DEBUG
            DebugSettingsSection()
#endif
        }
        .environment(\.defaultMinListHeaderHeight, 0)
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
    }
}
#endif
