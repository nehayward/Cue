import Foundation
import Observation
import SonosKit

/// Where the listener has been in each book: every start, pause and jump,
/// so a place that's lost — a skip that went too far, a chapter picked by
/// mistake, another device's place taken over this one's — is one tap
/// away. `AudiobookPlayer` records them as it follows playback; the
/// Chapters sheet and the book's page list them.
///
/// Kept apart from `AudiobookProgressStore`, which holds only the newest
/// place: whatever replaces that reading, the places before it stay here.
/// In a file in Application Support, the newest `limit` of each book.
@MainActor
@Observable
final class AudiobookPlaceHistory {
    static let shared = AudiobookPlaceHistory()

    /// One place in a book, and what happened there.
    struct Place: Codable, Hashable, Identifiable {
        enum Kind: String, Codable {
            /// Played from here.
            case started
            /// Paused here.
            case paused
            /// Left from here for somewhere else in the book: a chapter, a
            /// scrub, a skip, or a move nobody asked for.
            case jumpedFrom
            /// This device's place, before another player's (the server's)
            /// took over.
            case replaced
            /// Here when something else took the player.
            case left
        }

        var id = UUID()
        /// Book time.
        let position: TimeInterval
        let date: Date
        let kind: Kind
    }

    /// Each book's places, newest first, by `AudiobookProgressStore.key`.
    private(set) var places: [String: [Place]] = [:]

    /// How many places each book keeps.
    private static let limit = 50
    /// A place this close to the newest one, this soon after it, says
    /// nothing new (a pause and a play in the same spot).
    private static let samePlace: TimeInterval = 20
    private static let sameMoment: TimeInterval = 10 * 60

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private static let io = DispatchQueue(label: "dance.cue.audiobookPlaces", qos: .utility)

    private init() {
        if let url = Self.fileURL, let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode([String: [Place]].self, from: data) {
            places = stored
        }
    }

    func places(for book: PlayableContent) -> [Place] {
        places[AudiobookProgressStore.key(for: book)] ?? []
    }

    /// Notes `kind` at book time `position`, unless it's where the book's
    /// newest place already is.
    func record(_ kind: Place.Kind, at position: TimeInterval, for book: PlayableContent) {
        let key = AudiobookProgressStore.key(for: book)
        var list = places[key] ?? []
        if let newest = list.first,
           abs(newest.position - position) < Self.samePlace,
           Date.now.timeIntervalSince(newest.date) < Self.sameMoment {
            return
        }
        list.insert(Place(position: max(position, 0), date: .now, kind: kind), at: 0)
        places[key] = Array(list.prefix(Self.limit))
        scheduleSave()
    }

    /// Forgets a book's places, for one marked unplayed.
    func forget(_ book: PlayableContent) {
        guard places.removeValue(forKey: AudiobookProgressStore.key(for: book)) != nil else { return }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Writes now, for the app leaving the foreground.
    func save() {
        saveTask?.cancel()
        saveTask = nil
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(places) else { return }
        Self.io.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static var fileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("AudiobookPlaces.json")
    }
}
