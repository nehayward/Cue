import Foundation

/// What the watch's widgets and Smart Stack show, as the watch app last
/// left it in the app group: how much music is on the watch, what's still
/// to come down, and what's playing. The app writes it when any of that
/// changes and asks WidgetKit to reload; the widget extension only reads.
public struct WatchWidgetState: Codable, Equatable, Sendable {
    public var songsOnWatch: Int
    public var songsToDownload: Int
    public var bytesUsed: Int64
    public var nowPlayingTitle: String?
    public var nowPlayingArtist: String?
    public var isPlaying: Bool

    public init(songsOnWatch: Int, songsToDownload: Int, bytesUsed: Int64, nowPlayingTitle: String? = nil, nowPlayingArtist: String? = nil, isPlaying: Bool = false) {
        self.songsOnWatch = songsOnWatch
        self.songsToDownload = songsToDownload
        self.bytesUsed = bytesUsed
        self.nowPlayingTitle = nowPlayingTitle
        self.nowPlayingArtist = nowPlayingArtist
        self.isPlaying = isPlaying
    }

    public static let empty = WatchWidgetState(songsOnWatch: 0, songsToDownload: 0, bytesUsed: 0)

    /// Shared by the watch app and its widget extension.
    public static let appGroup = "group.dance.cue"
    static let defaultsKey = "watchWidgetState"

    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    public static func load(from defaults: UserDefaults? = sharedDefaults) -> WatchWidgetState {
        guard let data = defaults?.data(forKey: defaultsKey),
              let state = try? JSONDecoder().decode(WatchWidgetState.self, from: data) else { return .empty }
        return state
    }

    public func save(to defaults: UserDefaults? = WatchWidgetState.sharedDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults?.set(data, forKey: Self.defaultsKey)
    }
}
