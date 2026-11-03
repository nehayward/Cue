#if targetEnvironment(macCatalyst)
import Defaults
import OSLog
import SwiftUI
import UIKit

/// The panes of the Mac's Settings window, chosen from its toolbar. General
/// is Settings' own page without the rows the other panes have taken.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, services, playback, sonos, appearance, storage

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .services: "Services"
        case .playback: "Playback"
        case .sonos: "Sonos"
        case .appearance: "Appearance"
        case .storage: "Storage"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .services: "music.note.list"
        case .playback: "play.circle"
        case .sonos: "hifispeaker.2"
        case .appearance: "paintpalette"
        case .storage: "internaldrive"
        }
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
    /// General, where About is.
    static func place(of destination: RouterDestination) -> (pane: SettingsPane, page: RouterDestination?) {
        switch destination {
        case .servicePreferenceScreen: (.services, nil)
        case .settingsPage(.playback): (.playback, nil)
        case .settingsPage(.sonos): (.sonos, nil)
        case .settingsPage(.appearance): (.appearance, nil)
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
/// the window's scale (`InterfaceSize`) and its height the listener's, and
/// its frame and pane are kept for next time.
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

    /// SwiftUI's, from the main window (`DesktopShell`): the menu bar's
    /// command and the routers have no environment to read it from.
    @ObservationIgnored var openWindow: OpenWindowAction?
    @ObservationIgnored private weak var scene: UIWindowScene?
    @ObservationIgnored private var askedAt: Date?
    @ObservationIgnored private var frameObserver: WindowSizeObserver?
    @ObservationIgnored private let toolbarDelegate = SettingsToolbar()

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

    /// Whether `session` is the Settings window's, from its mark.
    static func isMarked(_ session: UISceneSession) -> Bool {
        session.userInfo?[sessionMark] as? Bool == true
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
        var info = scene.session.userInfo ?? [:]
        info[Self.sessionMark] = true
        scene.session.userInfo = info

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
        fit(scene, placing: true)
        frameObserver = WindowSizeObserver(windowScene: scene, store: .settings)
        Self.log.info("Settings window connected on \(self.pane.rawValue, privacy: .public)")
    }

    func disconnect(_ scene: UIScene) {
        guard scene === self.scene else { return }
        self.scene = nil
        frameObserver = nil
    }

    /// Fits the window's width to the window's scale, as it opens and when
    /// View ▸ Bigger or Smaller changes it.
    func fitToScale() {
        guard let scene else { return }
        fit(scene, placing: false)
    }

    /// Its width is fixed, a Mac app's settings' way, at Cue's scale; its
    /// height is free. `placing` puts it where it was left, else over the
    /// main window.
    private func fit(_ scene: UIWindowScene, placing: Bool) {
        let scale = DesktopStyle.scale(AppState.shared.interfaceSize.typeSize)
        let width = (Self.width * scale).rounded()
        scene.sizeRestrictions?.minimumSize = CGSize(width: width, height: (Self.minimumHeight * scale).rounded())
        scene.sizeRestrictions?.maximumSize = CGSize(width: width, height: .greatestFiniteMagnitude)

        // The system's frame is in the Mac's points, the scene's in the
        // iPad's (macOS draws an iPad app at 77%).
        let points = scene.effectiveGeometry.coordinateSpace.bounds.width
        let current = scene.effectiveGeometry.systemFrame
        let ratio = points > 0 && current.width > 0 ? current.width / points : 0.77
        var frame = current
        frame.size.width = width * ratio
        if placing {
            if let saved = WindowFrameStore.settings.savedFrame {
                frame.origin = saved.origin
                frame.size.height = saved.height
            } else {
                frame.size.height = Self.height * scale * ratio
                if let main = Self.mainWindowFrame(besides: scene) {
                    frame.origin = CGPoint(x: main.midX - frame.width / 2, y: main.midY - frame.height / 2)
                }
            }
        } else {
            frame.origin.x = current.midX - frame.width / 2
        }
        guard frame.size != .zero else { return }
        scene.requestGeometryUpdate(.Mac(systemFrame: frame)) { error in
            Self.log.error("Settings window frame: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func mainWindowFrame(besides settings: UIWindowScene) -> CGRect? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0 !== settings && !isMarked($0.session) }?
            .effectiveGeometry.systemFrame
    }

    /// In the iPad's points, at the default scale's 1.
    private static let width: CGFloat = 600
    private static let height: CGFloat = 620
    private static let minimumHeight: CGFloat = 400
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
        item.image = UIImage(systemName: pane.symbol)
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
        if pane == .general {
            // Settings' own page, with its own stack and router.
            PreferenceScreen(isWindowPane: true)
        } else {
            NavigationStack(path: $router.path) {
                root
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
    }

    @ViewBuilder
    private var root: some View {
        switch pane {
        case .general: EmptyView()
        case .services: ServicePreferenceScreen()
        case .playback: PlaybackSettingsScreen()
        case .sonos: SonosSettingsScreen()
        case .appearance: AppearanceSettingsScreen()
        case .storage: DownloadsScreen()
        }
    }
}
#endif
