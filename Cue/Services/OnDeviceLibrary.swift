import SonosKit

/// What plays with no connection at all: the download manager's finished
/// Plex and Subsonic songs, and the songs of the Files folder that are on
/// this device rather than only in iCloud. The Home tab shows just these
/// while `OfflineMode` is active.
@MainActor
enum OnDeviceLibrary {
    /// Every finished download as a playable song, by title. The local
    /// player finds the file through the download manager, so these play
    /// with the server unreachable.
    static var downloadedSongs: [PlayableContent] {
        DownloadManager.shared.completed
            .map(\.playableContent)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The Files folder's songs that are here: `isPlayable` follows the
    /// index's download flag, which a scan and an iCloud eviction both keep
    /// current. Everything for a folder on the device itself.
    static var fileSongs: [PlayableContent] {
        FilesLibraryService.shared.songs.filter(\.isPlayable)
    }

    /// Downloads then the folder — what Play and Shuffle on Home take.
    static var allSongs: [PlayableContent] {
        downloadedSongs + fileSongs
    }

    static var isEmpty: Bool {
        DownloadManager.shared.completed.isEmpty && fileSongs.isEmpty
    }
}

extension DownloadManager.Item {
    /// The download as the song it was queued from — enough for a row, a
    /// menu, and the local player, which resolves the file by the same key
    /// the download was stored under.
    var playableContent: PlayableContent {
        PlayableContent(
            title: title,
            subtitle: subtitle,
            thumbnail: artwork,
            artwork: artwork,
            content: .init(service: service, id: contentID, type: .track, location: nil),
            previewURL: url,
            metadata: .init(artist: subtitle, audioCodec: fileExtension)
        )
    }
}
