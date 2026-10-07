import Foundation
import OrderedCollections
import Observation
import os

@Observable
public final class Room: Identifiable, @unchecked Sendable {
    public let id: String
    public let ip: String
    public let name: String
    public let channelMap: String?
    public let satChannelMap: String?
    public var volume: Double = 0
    public var isMuted: Bool = false

    /// Until when a mute Cue just set holds against the poll. A read that
    /// left before the change landed would otherwise put the old state back.
    @ObservationIgnored public private(set) var muteHeldUntil: Date = .distantPast
    public var isMuteHeld: Bool { muteHeldUntil > .now }

    /// Shows `mute` at once and keeps the poll from undoing it while the
    /// speaker catches up.
    public func holdMute(_ mute: Bool) {
        muteHeldUntil = .now.addingTimeInterval(2.5)
        if isMuted != mute {
            isMuted = mute
        }
    }
    public var isPlaying: Bool = false {
        didSet {
            guard isPlaying != oldValue else { return }
            clockDidChange(wasRunning: oldValue && !isTransitioning)
        }
    }
    /// True while the transport reports TRANSITIONING — e.g. right after new
    /// content is queued and before playback actually starts — or the socket
    /// reports BUFFERING. UI uses this to pulse the play/pause button, and the
    /// progress clock stops for it: the speaker isn't moving through the song.
    public var isTransitioning: Bool = false {
        didSet {
            guard isTransitioning != oldValue else { return }
            clockDidChange(wasRunning: isPlaying && !oldValue)
        }
    }
    public var track: Track = .empty {
        didSet {
            // The position belongs to the track. A new song arrives carrying
            // the position the speaker reported with it, and that has to land
            // in the same step: nothing else is guaranteed to write it — a
            // report that agrees with the running clock is dropped, and
            // backgrounded there's no poll. The previous song's position used
            // to stay put, and every progress bar and the Lock Screen card ran
            // the new song on from where the old one was.
            guard track.unique != oldValue.unique else { return }
            seekTarget = nil
            playbackPosition = track.playbackPosition
        }
    }
    /// Current playback position (ms) as last reported by the device or set by a
    /// local seek. Lives on `Room` rather than `Track` so the high-frequency
    /// position pulses from Sonos don't fire `Room.track` observation and
    /// invalidate every consumer reading any track field.
    public var playbackPosition: TimeInterval = 0 {
        didSet { playbackPositionStampedAt = .now }
    }
    /// When `playbackPosition` was last written, or playback last started or
    /// stopped. See `estimatedPlaybackPosition(at:)`.
    @ObservationIgnored public private(set) var playbackPositionStampedAt: Date = .distantPast
    /// Where a seek was sent, until the speaker reports it got there. The
    /// estimate holds at this point in the meantime — see `beginSeek(to:at:)`.
    @ObservationIgnored public private(set) var seekTarget: TimeInterval?
    @ObservationIgnored private var seekStartedAt: Date = .distantPast
    /// When `isPlaying` was last set from a pushed (WebSocket) event. Read
    /// through `hasFreshPlaybackState` — see `markPlaybackState`.
    @ObservationIgnored public private(set) var playbackStateStampedAt: Date = .distantPast
    /// Radio Station Name
    public var radioStation: String?
    public var isEditingVolume: Bool = false
    public var isOutputFixed: Bool = false
    public var state: RoomState
    public var battery: Battery?
    public var macAddress: String?
    public var location: URL?
    public var wirelessMode: Int
    public var wirelessLeafOnly: Bool
    public var behindWifiExtender: Bool
    public var wifiEnabled: Bool
    public var ethernetEnabled: Bool
    public var voiceConfigState: Int
    public var micEnabled: Bool
    public var airPlayEnabled: Bool
    public var invisible: Bool
    public var info: DeviceInfo? = nil
    public var sleepTimer: Date? = nil
    public var alarmRunning: Bool = false
    /// For vanished/sleeping speakers, the UTC timestamp Sonos last
    /// reported them as reachable. Nil for currently-active rooms.
    public var lastSeen: Date? = nil
    public var subs: [Sub] = []
    public var queue: OrderedSet<PlayableContent> = []
    public var queueTotal: Int = 0
    public var container: SonosContainer?

    // MARK: Settings
    public var settings = SpeakerSettings(isSet: false)
    public var theaterSettings = TheaterSettings(isSet: false)

    public var isSoundbar: Bool {
        let keywords = ["Ray", "Beam", "Playbar", "Arc", "Amp", "Playbase"]
        if let info {
            return keywords.contains(where: info.modelDisplayName.contains)
        }
        return false
    }

    /// Model numbers (`DeviceInfo.model`) with the levelled Arc Ultra speech
    /// enhancement rather than the on/off `DialogLevel` every other soundbar has.
    /// The number is stable where `modelDisplayName` moves with locale and renames —
    /// the substring match below is the fallback for models not catalogued here.
    private static let arcUltraModelNumbers: Set<String> = ["S45"] // Sonos Arc Ultra

    public var isArcUltra: Bool {
        guard let info else { return false }
        let model = info.model.trimmingCharacters(in: .whitespaces).uppercased()
        if Self.arcUltraModelNumbers.contains(model) { return true }
        return info.modelDisplayName.lowercased().contains("arc ultra")
    }

    /// `nil` until the model is known. Guessing "not an Arc Ultra" from a missing
    /// model sends the wrong EQ command, so callers that can probe the speaker
    /// should treat `nil` as "ask it" rather than as `false`.
    public var isArcUltraIfKnown: Bool? {
        info == nil ? nil : isArcUltra
    }

    public var supportsLineIn: Bool {
        guard let info else { return false }
        // Prefer the device-reported capability — it's authoritative across firmware/models.
        if let capabilities = info.capabilities {
            return capabilities.contains("LINE_IN")
        }
        // Fallback when capabilities haven't been reported yet. "Era" and "Move 2" stay
        // broad — every Era (100/100 SL/300) and Move 2 supports line-in via the USB-C
        // adapter. "Play:5" and the 2026 portable "Play" both support it, but must be
        // matched precisely: the bare "Play" substring also caught Play:1/Play:3/Playbar/
        // Playbase, which have no line-in and wrongly surfaced the "Switch to Line In" action.
        let model = info.modelDisplayName
        // New portable "Sonos Play" — exact (last-token) match so we don't catch its siblings.
        if model.split(separator: " ").last == "Play" { return true }
        let keywords = ["Amp", "Connect", "Port", "Five", "Play:5", "Era", "Move 2"]
        return keywords.contains(where: model.contains)
    }
    
    public var supportsFixedOutput: Bool {
        let keywords = ["Port", "Connect"]
        if let info {
            return keywords.contains(where: info.modelDisplayName.contains)
        }
        return false
    }

    public init(
        id: String,
        ip: String,
        name: String,
        channelMap: String? = nil,
        satChannelMap: String? = nil,
        track: Track = .empty,
        state: RoomState = .active,
        battery: Battery? = nil,
        macAddress: String? = nil,
        location: URL? = nil,
        wirelessMode: Int = 1,
        wirelessLeafOnly: Bool = false,
        behindWifiExtender: Bool = false,
        wifiEnabled: Bool = true,
        ethernetEnabled: Bool = false,
        voiceConfigState: Int = 0,
        micEnabled: Bool = false,
        airPlayEnabled: Bool = false,
        invisible: Bool = false,
        isOutputFixed: Bool = false,
        subs: [Sub] = [],
        info: DeviceInfo? = nil,
        container: SonosContainer? = nil,
        lastSeen: Date? = nil
    ) {
        self.id = id
        self.ip = ip
        self.name = name
        self.channelMap = channelMap
        self.satChannelMap = satChannelMap
        self.track = track
        self.state = state
        self.battery = battery
        self.macAddress = macAddress
        self.location = location
        self.wirelessMode = wirelessMode
        self.wirelessLeafOnly = wirelessLeafOnly
        self.behindWifiExtender = behindWifiExtender
        self.wifiEnabled = wifiEnabled
        self.ethernetEnabled = ethernetEnabled
        self.voiceConfigState = voiceConfigState
        self.micEnabled = micEnabled
        self.airPlayEnabled = airPlayEnabled
        self.isOutputFixed = isOutputFixed
        self.invisible = invisible
        self.subs = subs
        self.info = info
        self.container = container
        self.lastSeen = lastSeen
    }
}

// MARK: - Playback position

extension Room {
    /// Where playback is now, not where it was last reported.
    ///
    /// `playbackPosition` only moves when something writes it — the pulse
    /// while the app is on screen, and only for the selected group; a socket
    /// event otherwise. So progress bars run it forward from when it was last
    /// written, the way the Lock Screen interpolates. That's what makes a bar
    /// right on its first frame, with nothing to catch up and nothing to
    /// animate into place.
    public func estimatedPlaybackPosition(at date: Date = .now) -> TimeInterval {
        position(at: date, running: isClockRunning)
    }

    /// Whether the speaker is actually moving through the song: playing, and
    /// not buffering or transitioning. A seek, a skip and a slow stream all
    /// spend a moment playing-but-not-moving, and a bar that counted through
    /// it ran ahead of the audio until the next report pulled it back.
    public var isClockRunning: Bool {
        isPlaying && !isTransitioning
    }

    /// Records a position the speaker reported.
    ///
    /// While the clock runs, a report within `reportTolerance` of the estimate
    /// is dropped: it was read a round trip ago, in whole seconds, so taking it
    /// would pull the bar back on every poll for a number no more accurate
    /// than the clock. While a seek is in flight, reports decide when it has
    /// landed — see `beginSeek(to:at:)`.
    public func updatePlaybackPosition(_ newValue: TimeInterval, at now: Date = .now) {
        if let target = activeSeekTarget(at: now) {
            // Anything well away from the target was read before the seek
            // landed.
            guard newValue >= target - 1000, newValue <= target + Self.seekTimeout * 1000 else { return }
            // Polls repeat the same number while the speaker buffers; a
            // position past the target always differs, so the confirmation
            // still restarts the clock.
            if newValue != playbackPosition { playbackPosition = newValue }
            // The speaker reports the target itself, and polls keep repeating
            // it, the whole time it buffers. Only a position past the target
            // while playing says the audio has actually resumed.
            if isClockRunning, newValue > target {
                seekTarget = nil
            }
            return
        }
        guard isClockRunning else {
            // Writing the same number still invalidates every view reading
            // it — for a paused room that was every poll.
            //
            // A poll reads whole seconds, rounded down; the socket reads the
            // same position to the millisecond. Paused, they took turns —
            // 1:48.65 from the socket, 1:48 from the next poll — so a time
            // rounded to the second, and the lyrics' fill, flickered between
            // them. A whole second that's what's held, rounded down, says
            // nothing new.
            let isHeldRoundedDown = newValue.truncatingRemainder(dividingBy: 1000) == 0
                && playbackPosition >= newValue && playbackPosition < newValue + 1000
            if newValue != playbackPosition, !isHeldRoundedDown { playbackPosition = newValue }
            return
        }
        guard abs(newValue - position(at: now, running: true)) >= Self.reportTolerance else { return }
        playbackPosition = newValue
    }

    /// Moves the bar to where a seek will land and holds it there until the
    /// speaker is playing from it.
    ///
    /// Two things made a scrub jump back a moment after letting go. The seek
    /// is sent in whole seconds (`REL_TIME` has no fraction), so the speaker
    /// lands up to a second short of where the finger stopped. And it then
    /// buffers before playing again, while the bar kept counting. So the bar
    /// goes to the second actually sought, and waits there — as the audio
    /// does.
    public func beginSeek(to target: TimeInterval, at now: Date = .now) {
        let landing = max((target / 1000).rounded(.down) * 1000, 0)
        seekTarget = landing
        seekStartedAt = now
        playbackPosition = landing
    }

    /// A skip, from this app: the bar goes to the start and holds there, the
    /// same as a seek, until the next song lands (its `track` write ends the
    /// hold) or the speaker reports playing from the start.
    ///
    /// Writing 0 on its own wasn't enough: for a moment after the command the
    /// speaker still reports the old song, far enough from the new clock to be
    /// taken, so the bar bounced back to where the old song was before the new
    /// one arrived.
    public func beginSkip(at now: Date = .now) {
        beginSeek(to: 0, at: now)
    }

    /// The seek still waiting to land, or nil — including once it has waited
    /// `seekTimeout` for a confirmation that never came, so a lost report
    /// can't hold the bar or filter reports forever.
    private func activeSeekTarget(at date: Date) -> TimeInterval? {
        guard let seekTarget, date.timeIntervalSince(seekStartedAt) < Self.seekTimeout else { return nil }
        return seekTarget
    }

    /// Stopping keeps the time that ran since the last report, so the bar stays
    /// where it was showing. Starting only restarts the clock: time spent
    /// stopped mustn't count.
    fileprivate func clockDidChange(wasRunning: Bool) {
        let now = Date.now
        if wasRunning, !isClockRunning {
            playbackPosition = position(at: now, running: true)
        }
        playbackPositionStampedAt = now
    }

    private func position(at date: Date, running: Bool) -> TimeInterval {
        guard running, activeSeekTarget(at: date) == nil, playbackPositionStampedAt != .distantPast else {
            return playbackPosition
        }
        let elapsed = max(date.timeIntervalSince(playbackPositionStampedAt) * 1000, 0)
        // Radio and line-in have no length to stop at.
        guard track.duration > 0 else { return playbackPosition + elapsed }
        return min(playbackPosition + elapsed, track.duration)
    }

    /// How long a seek waits to be confirmed before the bar runs without it.
    static let seekTimeout: TimeInterval = 3

    /// A poll reports whole seconds and lands a round trip late, so it runs up
    /// to about 1.3 s behind the clock on its own. Anything past this is the
    /// speaker actually being somewhere else (a seek, a skip, drift).
    static let reportTolerance: TimeInterval = 2000
}

extension Room {
    /// Where a playback-state write came from. The sources have very different
    /// latencies and authority, and until they went through one funnel they
    /// silently fought each other.
    public enum PlaybackStateSource: String {
        /// Pushed by the speaker over the WebSocket, ~100 ms after the fact.
        case socket
        /// A SOAP read — the pulse, a Live Activity refresh, a group sweep.
        /// Always a request/response behind whatever just happened.
        case poll
        /// An optimistic write from a user action, before the speaker confirms.
        case localCommand
    }

    /// The single way `isPlaying` should be written.
    ///
    /// Precedence: a pushed or user-initiated state wins over a polled one for
    /// two seconds. A SOAP response captured *before* a pause lands *after* the
    /// socket reported it, and would otherwise flip the flag back — invisible on
    /// screen, where the next poll corrects it, but on a Lock Screen card it
    /// reads as playback flickering.
    public func setPlaying(_ playing: Bool, source: PlaybackStateSource) {
        if source != .poll {
            // Stamped even when the value is unchanged: what matters is that a
            // fast source just spoke, not that it changed its mind.
            playbackStateStampedAt = .now
        } else if hasFreshPlaybackState, isPlaying != playing {
            return
        }
        guard isPlaying != playing else { return }
        isPlaying = playing
    }

    /// Writes `isTransitioning` from a poll. A tap on play/pause answers the
    /// button at once; the speaker then passes through TRANSITIONING on its
    /// way there, and pulsing the button for that window made the tap read as
    /// not having landed. Same two-second window as `setPlaying`.
    public func setTransitioning(_ transitioning: Bool) {
        let value = transitioning && !hasFreshPlaybackState
        guard isTransitioning != value else { return }
        isTransitioning = value
    }

    /// Applies a polled transport state, touching only what it actually says
    /// and only what changed: an `@Observable` setter notifies every observer
    /// even when the value is the same, and this runs on every sweep.
    public func apply(polled status: PlaybackStatus) {
        switch status {
        case .playing: setPlaying(true, source: .poll)
        case .paused: setPlaying(false, source: .poll)
        case .transitioning, .unknown: break
        }
        if let transitioning = status.isTransitioning {
            setTransitioning(transitioning)
        }
    }

    /// Whether a pushed playback state landed recently enough that a SOAP read
    /// shouldn't overwrite it. Poll intervals here are 500–800 ms, so two
    /// seconds covers a response that was already in flight.
    public var hasFreshPlaybackState: Bool {
        Date.now.timeIntervalSince(playbackStateStampedAt) < 2
    }
}

extension Room: Hashable {
    public static func == (lhs: Room, rhs: Room) -> Bool {
        lhs.id == rhs.id &&
        lhs.ip == rhs.ip &&
        lhs.name == rhs.name &&
        lhs.track.id == rhs.track.id &&
        lhs.track.artist == rhs.track.artist &&
        lhs.track.song == rhs.track.song &&
        lhs.radioStation == rhs.radioStation
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(ip)
        hasher.combine(state)
        hasher.combine(macAddress)
        hasher.combine(track.id)
        hasher.combine(track.artist)
        hasher.combine(track.song)
        hasher.combine(radioStation)
    }
}


extension Room: CustomStringConvertible {
    public var description: String {
        "\(name): \(volume)% [\(id)] [\(ip)]"
    }
}

extension Room {
    public static let garage = Room(
        id: "RINCON_B8E937525BB001400",
        ip: "192.168.4.50",
        name: "Garage",
        container: .init(
            images: nil,
            objectType: nil,
            service: .init(
                id: "12",
                name: "Spotify",
                images: [],
                objectType: nil
            ),
            htInputFormat: nil,
            type: "playlist",
            name: "Mood Booster",
            id: .init(
                accountId: nil,
                serviceId: "12",
                objectId: "spotify:playlist:37i9dQZF1DX3rxVfibe1L0",
                objectType: ""
            )
        )
    )
    public static let gym = Room(id: "RINCON_7828CAC7352E01400", ip: "192.168.4.49", name: "Gym")
    public static let theater = Room(id: "RINCON_48A6B80D8FB401400", ip: "192.168.4.144", name: "Theater", track: Track(trackID: "134"))
    public static let theaterFixed = Room(id: "RINCON_48A6B80D8FB401400", ip: "192.168.4.144", name: "Theater", track: Track(trackID: "134"), isOutputFixed: true)
    public static let livingRoom = Room(id: "RINCON_949F3E6FBAE401400", ip: "192.168.4.48", name: "Living Room")
    public static let garage_kitchen_display = Room(id: "RINCON_48A6B80D8FB401400", ip: "192.168.4.144", name: "Kitchen")
}
