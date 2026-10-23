import Defaults
import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI

/// What Audible knows of each author (`AudnexusAuthor`: picture, biography,
/// genres), kept in Caches by name, so an author's page opened again
/// doesn't ask. Observed: a page reads its author here and redraws when an
/// answer lands. Someone Audible doesn't know is asked again after a day,
/// someone it does after a month; with Audnexus out of reach, what was
/// kept stands.
@MainActor
@Observable
final class AudiobookAuthorInfo {
    static let shared = AudiobookAuthorInfo()

    private struct Entry: Codable, Sendable {
        var author: AudnexusAuthor?
        var askedAt: Date

        /// Asked recently enough to stand.
        var isFresh: Bool {
            let lifetime: TimeInterval = author == nil ? 24 * 60 * 60 : 30 * 24 * 60 * 60
            return Date.now.timeIntervalSince(askedAt) < lifetime
        }
    }

    private static let fileName = "AudiobookAuthors.json"

    private var entries = CachesWriter.read([String: Entry].self, from: AudiobookAuthorInfo.fileName) ?? [:]
    /// Names being asked about now, so a page opened twice asks once.
    @ObservationIgnored private var asking: Set<String> = []

    private init() {}

    /// Audible's record of `name` as last kept, without asking; nil when it
    /// has none, or hasn't been asked.
    func author(named name: String) -> AudnexusAuthor? {
        entries[name.lowercased()]?.author
    }

    /// Asks Audible about `name` unless what's kept is recent enough. The
    /// answer lands in `author(named:)`.
    func refresh(named name: String) {
        let key = name.lowercased()
        guard entries[key]?.isFresh != true, asking.insert(key).inserted else { return }
        Task {
            defer { asking.remove(key) }
            switch await AudnexusAPI.author(named: name) {
            case let .found(author):
                remember(author, for: key)
            case .notFound:
                remember(nil, for: key)
            case .unreachable:
                break
            }
        }
    }

    private func remember(_ author: AudnexusAuthor?, for key: String) {
        entries[key] = Entry(author: author, askedAt: .now)
        let entries = entries
        Task { await CachesWriter.shared.write(entries, to: Self.fileName) }
    }
}
