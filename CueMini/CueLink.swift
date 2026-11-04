import AppKit
import Observation
import OSLog

/// Cue's player as Cue (Mac) last sent it (`CueMiniNowPlaying`, from
/// `CueMiniLink` on Cue's side), and the way back to it: commands sent as
/// distributed notifications, run by Cue on whatever its player shows, on
/// this Mac or a Sonos group.
///
/// Cue sends only when something changes, and when asked: this asks
/// (`CueMiniCommand.refresh`) as Mini launches and as its menu opens. A
/// state is believed only while the Cue that sent it is running
/// (`processID`): Cue quit, Mini says so.
@MainActor
@Observable
final class CueLink {
    static let shared = CueLink()

    nonisolated private static let log = Logger(subsystem: "dance.cue.mini", category: "cue")

    /// Cue's Sonos setting as last heard, for while Cue is closed. Mini's
    /// own defaults, written only when it changes.
    private static let sonosEnabledKey = "cueSonosEnabled"

    /// The running Cue's process, nil while Cue isn't open.
    private(set) var cueProcessID: pid_t?
    /// The last state Cue sent.
    private(set) var latest: CueMiniNowPlaying?
    /// The last cover Cue sent, and what it's the cover of.
    private(set) var cover: (key: String, image: NSImage)?
    /// That cover as a file in Mini's caches, for the HUD, which loads a URL.
    @ObservationIgnored private(set) var coverFileURL: URL?
    /// Cue's Sonos setting as last heard.
    private(set) var sonosEnabled: Bool?

    /// Told when the song on this Mac changes, for the track-change HUD. A
    /// speaker's songs have the speaker's own (`SonosMiniService.onTrackChanged`).
    @ObservationIgnored var onTrackChanged: (@MainActor (CueMiniNowPlaying) -> Void)?
    /// The song the HUD last went up for, and when, to bring its cover in
    /// when it lands just after.
    @ObservationIgnored private var announced: (id: String, at: Date)?

    var isCueRunning: Bool { cueProcessID != nil }

    /// Cue's player, while the Cue that sent it runs.
    var state: CueMiniNowPlaying? {
        guard let latest, let cueProcessID, latest.processID == cueProcessID else { return nil }
        return latest
    }

    /// The cover of the item on show, once it's here.
    var currentCover: NSImage? {
        guard let key = state?.item?.artworkKey, let cover, cover.key == key else { return nil }
        return cover.image
    }

    /// Whether to show and look for Sonos speakers: as Cue's own setting
    /// was last heard, and yes before it ever has been.
    var showsSpeakers: Bool {
        sonosEnabled ?? true
    }

    /// The Sonos group Cue plays on, by its coordinator; nil for this Mac.
    var speakerGroupID: String? {
        state?.route.groupID
    }

    private init() {
        sonosEnabled = UserDefaults.standard.object(forKey: Self.sonosEnabledKey) as? Bool
        refreshRunning()

        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Notification.Name(CueMiniNowPlaying.changedNotification), object: nil, queue: .main) { notification in
            let state = CueMiniNowPlaying(notificationObject: notification.object)
            MainActor.assumeIsolated {
                if let state { CueLink.shared.receive(state) }
            }
        }
        center.addObserver(forName: Notification.Name(CueMiniCover.notificationName), object: nil, queue: .main) { notification in
            let cover = CueMiniCover(notificationObject: notification.object)
            MainActor.assumeIsolated {
                if let cover { CueLink.shared.receive(cover) }
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == CueMiniNowPlaying.cueBundleIdentifier else { return }
                MainActor.assumeIsolated {
                    CueLink.shared.refreshRunning()
                }
            }
        }

        // What Cue's playing, should it be open as Mini starts.
        send(.refresh)
    }

    // MARK: - Hearing from Cue

    private func refreshRunning() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: CueMiniNowPlaying.cueBundleIdentifier)
            .filter { !$0.isTerminated }
        // The one that sent last, should two be running.
        let pid = running.first { $0.processIdentifier == latest?.processID }?.processIdentifier
            ?? running.first?.processIdentifier
        guard pid != cueProcessID else { return }
        cueProcessID = pid
        Self.log.info("Cue \(pid == nil ? "closed" : "running", privacy: .public)")
    }

    private func receive(_ new: CueMiniNowPlaying) {
        guard new.version == CueMiniNowPlaying.currentVersion else { return }
        let previous = state
        latest = new
        // A Cue that started after Mini last looked.
        if new.processID != cueProcessID { refreshRunning() }
        if sonosEnabled != new.sonosEnabled {
            sonosEnabled = new.sonosEnabled
            UserDefaults.standard.set(new.sonosEnabled, forKey: Self.sonosEnabledKey)
        }
        noteTrackChange(from: previous)
    }

    private func receive(_ new: CueMiniCover) {
        guard cover?.key != new.key, let image = NSImage(data: new.jpeg) else { return }
        cover = (new.key, image)
        coverFileURL = Self.writeCoverFile(new)
        // The cover lands a moment after the song: put it in the HUD that
        // went up for it.
        if let state, let item = state.item, item.artworkKey == new.key,
           let announced, announced.id == item.id, Date.now.timeIntervalSince(announced.at) < 3 {
            onTrackChanged?(state)
        }
    }

    /// Keeps `cover` in Mini's caches, the one before it taken away.
    private static func writeCoverFile(_ cover: CueMiniCover) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = caches.appendingPathComponent("CueCover", isDirectory: true)
        let file = directory.appendingPathComponent("\(cover.key).jpg")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for old in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where old != file.lastPathComponent {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(old))
            }
            try cover.jpeg.write(to: file, options: .atomic)
            return file
        } catch {
            log.error("couldn't keep the cover: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The cover's file, for the HUD, when it's the item on show's.
    var coverURL: URL? {
        guard let key = state?.item?.artworkKey, cover?.key == key else { return nil }
        return coverFileURL
    }

    private func noteTrackChange(from previous: CueMiniNowPlaying?) {
        guard let state, let item = state.item, previous != nil, !state.route.isSpeaker, state.isPlaying,
              previous?.item?.id != item.id else { return }
        announced = (item.id, .now)
        onTrackChanged?(state)
    }

    // MARK: - Commands

    /// Sends `command` to Cue's player, and shows what it'll do at once:
    /// Cue's own word follows in a moment.
    func send(_ command: CueMiniCommand) {
        guard isCueRunning, let object = command.notificationObject else { return }
        applyOptimistically(command)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(CueMiniCommand.notificationName),
            object: object,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func applyOptimistically(_ command: CueMiniCommand) {
        guard var state, state.isActive else { return }
        let now = Date.now
        switch command {
        case .togglePlayback:
            state.clock.position = state.clock.position(at: now)
            state.clock.readAt = now
            state.isPlaying.toggle()
            state.clock.isRunning = state.isPlaying
        case .seek(let seconds, let itemID):
            guard state.item?.id == itemID else { return }
            state.clock.position = max(seconds - state.clock.spanStart, 0)
            state.clock.readAt = now
        case .setShuffle(let on):
            state.isShuffled = on
        case .setRepeat(let mode):
            state.repeatMode = mode
        case .next, .previous, .skip, .refresh:
            return
        }
        latest = state
    }

    /// Previous or Next, or a book's skips in their places.
    func skip(forward: Bool) {
        guard let state, state.item != nil else { return }
        let transport = state.transport
        if let seconds = forward ? transport.skipForward : transport.skipBack {
            send(.skip(seconds: forward ? seconds : -seconds))
        } else {
            send(forward ? .next : .previous)
        }
    }

    // MARK: - Opening Cue

    /// Opens Cue's player: brings Cue forward, launching it if it isn't
    /// open, on its `cue://playing` link.
    func showPlayer() {
        guard let url = URL(string: "cue://playing") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens Cue as it was.
    func openCue() {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CueMiniNowPlaying.cueBundleIdentifier) else {
            if let url = URL(string: "cue://") { NSWorkspace.shared.open(url) }
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                Self.log.error("couldn't open Cue: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
