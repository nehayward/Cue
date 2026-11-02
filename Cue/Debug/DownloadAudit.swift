#if DEBUG
import Foundation
import OSLog
import SonosKit
import UIKit

/// Drives downloads from launch arguments, so they can be exercised on a
/// device without anyone tapping it (`devicectl device process launch …
/// dance.cue -- <arguments>`). Debug builds only; logs go to the
/// `downloads` category.
///
///   -DownloadPlexPlaylist "❤️ Tracks"     a playlist by title, or part of one
///   -DownloadPlexAlbum "Abbey Road"       the first album a search finds
///   -DownloadSubsonicPlaylist "Road Trip"
///   -DownloadSubsonicAlbum "Rumours"
///   -DownloadAuditReset YES               remove every download first
///   -DownloadAuditCancelAfter 10          cancel the lot that many seconds in
///   -DownloadAuditWatch YES               log each download's speed every 5 s
///   -DownloadAuditNoCard YES              no continued-processing task
///   -DownloadWindow 4                     downloads on the session at once
///   -RemovePlexAlbum "Future Nostalgia"   remove an album's download
///   -RemoveDownloadedSong "Houdini"       remove one song's download
///   -ListPlexPlaylists YES                list every playlist as a download would
///   -ListSubsonic YES                     Subsonic playlists and recent albums
///
/// While a batch runs it logs where it stands every five seconds.
@MainActor
enum DownloadAudit {
    private static let log = Logger(subsystem: "dance.cue", category: "downloads")

    static func runIfAsked() {
        let defaults = UserDefaults.standard
        let playlist = defaults.string(forKey: "DownloadPlexPlaylist")
        let album = defaults.string(forKey: "DownloadPlexAlbum")
        let subsonicPlaylist = defaults.string(forKey: "DownloadSubsonicPlaylist")
        let subsonicAlbum = defaults.string(forKey: "DownloadSubsonicAlbum")
        if defaults.bool(forKey: "ListSubsonic") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                let search = MusicSearchService.shared
                for playlist in await search.subsonicUserPlaylists() {
                    let songs = await search.containerTracks(for: playlist)
                    log.info("Audit: subsonic playlist \(playlist.title, privacy: .public): \(songs.count) songs")
                }
                for album in await search.subsonicRecentAlbums().prefix(15) {
                    let songs = await search.containerTracks(for: album)
                    log.info("Audit: subsonic album \(album.title, privacy: .public) by \(album.subtitle, privacy: .public): \(songs.count) songs")
                }
                log.info("Audit: done")
            }
        }
        // `-RemovePlexAlbum "Future Nostalgia"` removes that album's download
        // and logs what's left of every other.
        if let removal = defaults.string(forKey: "RemovePlexAlbum") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                let manager = DownloadManager.shared
                guard let match = await MusicSearchService.shared.searchPlexAlbums(query: removal).first else {
                    log.error("Audit: no album like \(removal, privacy: .public)")
                    return
                }
                manager.removeDownload(contentsOf: match)
                log.info("Audit: removed \(match.title, privacy: .public)")
                for container in manager.containers.values {
                    let counts = manager.trackCounts(forContainer: container.key)
                    log.info("Audit: left \(container.title, privacy: .public) \(counts.downloaded)/\(counts.total), state \(String(describing: manager.containerState(key: container.key)), privacy: .public)")
                }
                log.info("Audit: done")
            }
        }
        // `-DownloadAuditWatch YES` logs every unfinished download's bytes
        // every five seconds, to see how fast each one moves.
        if defaults.bool(forKey: "DownloadAuditWatch") {
            Task { @MainActor in
                let manager = DownloadManager.shared
                var last: [String: Int64] = [:]
                while true {
                    try? await Task.sleep(for: .seconds(5))
                    let active = manager.items.values.filter { $0.state != .completed }.sorted { $0.title < $1.title }
                    let total = active.reduce(Int64(0)) { $0 + $1.bytesReceived - (last[$1.key] ?? $1.bytesReceived) }
                    let rows = active.map { item in
                        let rate = Double(item.bytesReceived - (last[item.key] ?? item.bytesReceived)) / 5 / 1_000_000
                        return "\(item.title) \(item.state.rawValue) \(item.bytesReceived / 1_000_000)/\(item.bytesExpected / 1_000_000) MB \(String(format: "%.2f", rate)) MB/s"
                    }
                    last = Dictionary(uniqueKeysWithValues: active.map { ($0.key, $0.bytesReceived) })
                    let state = switch UIApplication.shared.applicationState {
                    case .active: "active"
                    case .inactive: "inactive"
                    default: "background"
                    }
                    log.info("Watch: [\(state, privacy: .public)] \(String(format: "%.2f", Double(total) / 5 / 1_000_000), privacy: .public) MB/s | \(rows.joined(separator: " | "), privacy: .public)")
                    let summary = await manager.sessionTaskSummary()
                    log.info("Watch: session \(summary, privacy: .public)")
                    if active.isEmpty { break }
                }
            }
        }
        // `-RemoveDownloadedSong "Houdini"` removes that one song and logs
        // what's left of every album and playlist.
        if let title = defaults.string(forKey: "RemoveDownloadedSong") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                let manager = DownloadManager.shared
                if let song = manager.items.values.first(where: { $0.title == title }) {
                    manager.remove(key: song.key)
                    log.info("Audit: removed song \(title, privacy: .public)")
                } else {
                    log.error("Audit: no downloaded song \(title, privacy: .public)")
                }
                for container in manager.containers.values {
                    let counts = manager.trackCounts(forContainer: container.key)
                    log.info("Audit: left \(container.title, privacy: .public) \(counts.downloaded)/\(counts.total), \(container.removedKeys?.count ?? 0) removed, state \(String(describing: manager.containerState(key: container.key)), privacy: .public)")
                }
                log.info("Audit: done")
            }
        }
        // `-ListPlexPlaylists YES` lists every playlist's songs the way a
        // download does, without downloading, to check the paging.
        if defaults.bool(forKey: "ListPlexPlaylists") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                let search = MusicSearchService.shared
                for playlist in await search.plexUserPlaylists() {
                    let started = Date.now
                    let songs = await search.allPlexPlaylistSongs(id: playlist.content.id)
                    let unique = Set((songs ?? []).map(DownloadManager.key(for:))).count
                    let first = await search.lookupPlexPlaylists(id: playlist.content.id).0
                    log.info("Audit: list \(playlist.title, privacy: .public): \(songs.map { "\($0.count)" } ?? "failed", privacy: .public) songs, \(unique) unique, server says \(first ?? -1), \(Date.now.timeIntervalSince(started), format: .fixed(precision: 2)) s")
                }
                log.info("Audit: done")
            }
        }
        guard playlist != nil || album != nil || subsonicPlaylist != nil || subsonicAlbum != nil else { return }
        // `-DownloadAuditReset YES` removes every download first, so a run
        // starts from nothing.
        if defaults.bool(forKey: "DownloadAuditReset") {
            let manager = DownloadManager.shared
            for key in manager.containers.keys { manager.removeContainer(key: key) }
            for key in manager.items.keys { manager.remove(key: key) }
        }
        Task { @MainActor in
            // The Plex server and its connection are resolved on launch.
            try? await Task.sleep(for: .seconds(4))
            let search = MusicSearchService.shared
            var containers: [PlayableContent] = []
            if let playlist {
                let all = await search.plexUserPlaylists()
                if let match = all.first(where: { $0.title == playlist }) ?? all.first(where: { $0.title.localizedCaseInsensitiveContains(playlist) }) {
                    containers.append(match)
                } else {
                    log.error("Audit: no playlist like \(playlist, privacy: .public) among \(all.map(\.title).joined(separator: ", "), privacy: .public)")
                }
            }
            if let album {
                if let match = await search.searchPlexAlbums(query: album).first {
                    containers.append(match)
                } else {
                    log.error("Audit: no album like \(album, privacy: .public)")
                }
            }
            if let subsonicPlaylist {
                let all = await search.subsonicUserPlaylists()
                if let match = all.first(where: { $0.title == subsonicPlaylist }) ?? all.first(where: { $0.title.localizedCaseInsensitiveContains(subsonicPlaylist) }) {
                    containers.append(match)
                } else {
                    log.error("Audit: no Subsonic playlist like \(subsonicPlaylist, privacy: .public) among \(all.map(\.title).joined(separator: ", "), privacy: .public)")
                }
            }
            if let subsonicAlbum {
                if let match = await search.searchSubsonicAlbums(query: subsonicAlbum).first {
                    containers.append(match)
                } else {
                    log.error("Audit: no Subsonic album like \(subsonicAlbum, privacy: .public)")
                }
            }
            let manager = DownloadManager.shared
            for container in containers {
                let started = Date.now
                let result = await manager.download(contentsOf: container)
                log.info("Audit: \(container.title, privacy: .public) queued \(result.queued), held back \(result.heldBack), couldn't load \(result.couldNotLoad) in \(Date.now.timeIntervalSince(started), format: .fixed(precision: 2)) s")
            }
            // `-DownloadAuditCancelAfter 10` cancels the lot that many
            // seconds in, for a container too big to keep.
            let cancelAfter = defaults.integer(forKey: "DownloadAuditCancelAfter")
            if cancelAfter > 0 {
                try? await Task.sleep(for: .seconds(cancelAfter))
                let started = Date.now
                containers.forEach(manager.removeDownload(contentsOf:))
                log.info("Audit: cancelled in \(Date.now.timeIntervalSince(started), format: .fixed(precision: 3)) s; \(manager.items.count) downloads left")
                containers = []
            }
            while !containers.isEmpty {
                try? await Task.sleep(for: .seconds(5))
                for container in containers {
                    let key = DownloadManager.containerKey(for: container)
                    let counts = manager.trackCounts(forContainer: key)
                    let stopped = manager.stoppedTrackCount(forContainer: key)
                    log.info("Audit: \(container.title, privacy: .public) \(counts.downloaded)/\(counts.total), \(stopped) stopped, state \(String(describing: manager.containerState(key: key)), privacy: .public)")
                }
                // Done once every track has landed or stopped.
                containers.removeAll { container in
                    let keys = manager.containers[DownloadManager.containerKey(for: container)]?.trackKeys ?? []
                    return !keys.contains { manager.items[$0]?.isActive == true }
                }
            }
            log.info("Audit: done")
        }
    }
}
#endif
