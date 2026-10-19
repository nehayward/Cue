import Foundation
import MusicSearchKit
import SonosKit

/// A book ready to play: its files as tracks, laid end to end, with its
/// chapters and where the server says it was left.
///
/// The book itself is the `.audiobook` item a shelf lists; `parts` are the
/// `.track`s the player plays. Everything the listener sees — the position,
/// the chapter, what's left — is in book time (`timeline`), which the
/// player's file and offset map onto.
struct Audiobook: Equatable, Codable {
    let book: PlayableContent
    var parts: [PlayableContent]
    let timeline: AudiobookTimeline
    let chapters: [AudiobookChapter]
    /// Narrator and the like, for the book's page; nil where the server
    /// doesn't say.
    var narrator: String?
    var summary: String?
    /// Where the server has the listener, as read when the book was loaded.
    var serverProgress: AudiobookProgress?

    var duration: TimeInterval { timeline.duration }

    /// The file a player item is, or nil when it isn't one of this book's.
    /// Rows that came back from a speaker don't always carry the id they
    /// went with: Plex matches by rating key, Audiobookshelf by its part.
    func partIndex(of item: PlayableContent?) -> Int? {
        guard let item, item.content.type == .track else { return nil }
        if item.content.service == .plex, let key = item.plexRatingKey {
            return parts.firstIndex { $0.plexRatingKey == key }
        }
        // A speaker's row names a session track by index, a file URL by
        // file id; either finds the file.
        if item.content.service == .audiobookshelf, let id = AudiobookshelfPartID(item.content.id) {
            return parts.firstIndex { AudiobookshelfPartID($0.content.id)?.isSameFile(as: id) ?? false }
        }
        return parts.firstIndex { $0.content.id == item.content.id && $0.content.service == item.content.service }
    }

    /// Book time for a place in one of its files.
    func time(part: Int, offset: TimeInterval) -> TimeInterval {
        timeline.time(part: part, offset: offset)
    }

    func chapter(at time: TimeInterval) -> AudiobookChapter? {
        chapters.chapter(at: time)
    }
}
