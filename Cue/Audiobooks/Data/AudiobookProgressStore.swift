import Foundation
import MusicSearchKit
import Observation
import SonosKit

/// Where the listener is in each book, on this device, in a file in
/// Application Support.
///
/// This device's reading is one of two: the server keeps its own (Plex
/// where each file was left, Audiobookshelf the book's progress), which
/// another player may have moved since. `AudiobookLibrary` compares the
/// two when a book is opened, and the newer wins; listening here writes
/// both.
///
/// Books are keyed by service and id (`key(for:)`), so a book reads the
/// same wherever it's opened from.
///
/// The books on the Apple Watch keep their places there too: the watch's
/// newer ones come in here, and these go out to it
/// (`WatchSyncService.bookPlacesDidChange`).
@MainActor
@Observable
final class AudiobookProgressStore {
    static let shared = AudiobookProgressStore()

    /// Each book's reading, by `key(for:)`.
    private(set) var readings: [String: AudiobookProgress] = [:]

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private static let io = DispatchQueue(label: "dance.cue.audiobookProgress", qos: .utility)

    private init() {
        if let url = Self.fileURL, let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode([String: AudiobookProgress].self, from: data) {
            readings = stored
        }
    }

    static func key(for book: PlayableContent) -> String {
        key(service: book.content.service, id: book.content.id)
    }

    static func key(service: MusicService, id: String) -> String {
        "\(service.sonosRawValue)|\(id)"
    }

    func progress(for book: PlayableContent) -> AudiobookProgress? {
        readings[Self.key(for: book)]
    }

    /// Notes a reading. A reading older than the one held is dropped, so a
    /// slow server answer can't take the listener back.
    func record(_ reading: AudiobookProgress, for book: PlayableContent) {
        record(reading, key: Self.key(for: book))
    }

    /// The same, for a book known by its server and id — the server's
    /// readings for a whole shelf at once.
    func record(_ reading: AudiobookProgress, service: MusicService, id: String) {
        record(reading, key: Self.key(service: service, id: id))
    }

    private func record(_ reading: AudiobookProgress, key: String) {
        if let held = readings[key], held.updatedAt > reading.updatedAt { return }
        guard readings[key] != reading else { return }
        readings[key] = reading
        scheduleSave()
        WatchSyncService.shared.bookPlacesDidChange()
    }

    /// Notes the server's reading of a book read whole, kept only when it
    /// beats this device's by the book's own rule
    /// (`AudiobookLibrary.preferring`): a server a few seconds behind this
    /// device's own play mustn't take it back, nor a Plex file counted
    /// played take this device's place in it.
    func recordServerProgress(of audiobook: Audiobook) {
        guard let reading = audiobook.serverProgress,
              AudiobookLibrary.preferring(local: progress(for: audiobook.book), server: reading, in: audiobook) == reading else { return }
        record(reading, for: audiobook.book)
    }

    /// The same for a book known by its server and id, from a reading with
    /// a place in it (Audiobookshelf's, for a whole shelf at once): kept
    /// only when it's clearly newer (`AudiobookProgress.preferring`).
    func recordFromServer(_ reading: AudiobookProgress, service: MusicService, id: String) {
        let key = Self.key(service: service, id: id)
        guard AudiobookProgress.preferring(local: readings[key], server: reading) == reading else { return }
        record(reading, key: key)
    }

    /// Forgets this device's reading, for a book marked unplayed.
    func forget(_ book: PlayableContent) {
        guard readings.removeValue(forKey: Self.key(for: book)) != nil else { return }
        scheduleSave()
    }

    /// Forgets every reading of `service`'s books, for a sign-out: they're
    /// that account's places, and the next account signed in would
    /// otherwise be sent them as its own (`AudiobookLibrary.load`).
    func forgetAll(of service: MusicService) {
        let prefix = "\(service.sonosRawValue)|"
        let kept = readings.filter { !$0.key.hasPrefix(prefix) }
        guard kept.count != readings.count else { return }
        readings = kept
        scheduleSave()
    }

    /// Writes a beat after the last change: a playing book records every
    /// few seconds, and one write covers a burst.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Writes now, for the app going to the background.
    func save() {
        saveTask?.cancel()
        saveTask = nil
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(readings) else { return }
        Self.io.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static var fileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("AudiobookProgress.json")
    }
}
