import Defaults
import Foundation
import Observation
import SonosKit

/// Books taken out of Continue Listening, each with when. A book stays out
/// until it's listened to again after that, here or on its server (its
/// reading moves on), and then comes back by itself. Kept on this device,
/// by the progress store's key (`AudiobookProgressStore.key(for:)`).
@MainActor
@Observable
final class ContinueListeningRemovals {
    static let shared = ContinueListeningRemovals()

    /// When each book was taken out.
    private(set) var removed: [String: Date]
    /// Counts removals, for a list of the books to read again on each
    /// (`PlayableListView.changeToken`).
    private(set) var version = 0

    private init() {
        let stored = UserDefaults.standard.dictionary(forKey: AppStorageKeys.continueListeningRemovals) as? [String: Date] ?? [:]
        // Those listened to since are back, and needn't be kept.
        let progress = AudiobookProgressStore.shared
        removed = stored.filter { key, at in
            (progress.readings[key]?.updatedAt ?? .distantPast) <= at
        }
        if removed.count != stored.count { save() }
    }

    func remove(_ book: PlayableContent) {
        removed[AudiobookProgressStore.key(for: book)] = .now
        version += 1
        save()
    }

    /// Whether `book` is in Continue Listening now: listened to (this
    /// device's history, Audiobookshelf's books in progress), not finished,
    /// and not taken out since. For its menu's Remove.
    func isListed(_ book: PlayableContent) -> Bool {
        guard !isRemoved(book), AudiobookProgressStore.shared.progress(for: book)?.isFinished != true else { return false }
        return AudiobookLibrary.listenedBooks(plex: true, audiobookshelf: true).contains { $0.isSameBook(as: book) }
    }

    /// Whether `book` is out of Continue Listening: taken out, and not
    /// listened to since.
    func isRemoved(_ book: PlayableContent) -> Bool {
        guard let at = removed[AudiobookProgressStore.key(for: book)] else { return false }
        return (AudiobookProgressStore.shared.progress(for: book)?.updatedAt ?? .distantPast) <= at
    }

    private func save() {
        UserDefaults.standard.set(removed, forKey: AppStorageKeys.continueListeningRemovals)
    }
}
