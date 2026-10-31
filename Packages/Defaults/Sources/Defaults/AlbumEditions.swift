import Foundation

/// An artist's albums, each once: the rules the artist page's Albums and
/// the discography widget's both go by, so the two list the same albums.
///
/// An album's remasters, new mixes and deluxe editions ("Abbey Road (2019
/// Mix)", "Future Nostalgia (The Moonlight Edition)") count as that album,
/// shown by its plain title and dated when it first came out: Apple keeps a
/// reissue's first release date, so the earliest edition's is the album's.
/// A release listed twice the same day is one album too. Albums that only
/// share words are their own ("Tha Carter II" isn't "Tha Carter"), as are
/// re-recordings ("Fearless (Taylor's Version)") and albums of one title
/// out on different days (Weezer's self-titled albums, as Plex can tag
/// them).
public enum AlbumEditions {
    public struct Album<Item> {
        /// The edition kept: the one titled plainly, else the earliest.
        public let item: Item
        /// The title without its edition: "Abbey Road".
        public let title: String
        /// When the album first came out, over every edition of it.
        public let released: Date?
    }

    /// `items`, each album once, newest first.
    ///
    /// - Parameters:
    ///   - editions: every release of the artist's that can date an album,
    ///     when there are more than `items` (an album list that names only
    ///     a reissue of one).
    ///   - byTitle: whether the titles decide what's an album, with no list
    ///     of albums to go by: no EPs, live recordings or DJ mixes.
    public static func albums<Item>(
        _ items: [Item],
        editions: [Item]? = nil,
        byTitle: Bool = false,
        title: (Item) -> String,
        released: (Item) -> Date?
    ) -> [Album<Item>] {
        // When each album's editions first came out.
        var firstOut: [String: Date] = [:]
        for item in editions ?? items where title(item) != plainTitle(title(item)) {
            guard let date = released(item) else { continue }
            let key = plainTitle(title(item)).lowercased()
            firstOut[key] = min(firstOut[key] ?? date, date)
        }
        var kept: [Album<Item>] = []
        let oldestFirst = items.sorted { (released($0) ?? .distantFuture) < (released($1) ?? .distantFuture) }
        for item in oldestFirst {
            let full = title(item)
            let lowered = full.lowercased()
            if byTitle, !isAlbum(titled: full) { continue }
            let plain = plainTitle(full)
            let key = plain.lowercased()
            let isEdition = lowered != key
            let date = released(item)
            let earliest = [date, firstOut[key]].compactMap(\.self).min()
            if let index = kept.firstIndex(where: { other in
                guard other.title.lowercased() == key else { return false }
                // An edition, or one of them is: the same album. Two plain
                // ones are the same only as one listed twice the same day.
                let otherIsEdition = title(other.item).lowercased() != key
                return isEdition || otherIsEdition || isSameDay(other.released, date)
            }) {
                // The one titled plainly stands for the album.
                if !isEdition, title(kept[index].item).lowercased() != key {
                    kept[index] = Album(item: item, title: plain, released: [kept[index].released, earliest].compactMap(\.self).min())
                }
                continue
            }
            kept.append(Album(item: item, title: plain, released: isEdition ? earliest : date.map { min($0, firstOut[key] ?? $0) }))
        }
        return kept.sorted { ($0.released ?? .distantPast) > ($1.released ?? .distantPast) }
    }

    /// Whether a title reads as an album, for when the titles decide: not
    /// an EP, a live recording, a DJ mix ("Club Future Nostalgia (DJ Mix)",
    /// which a service can file as an album) or remixes.
    public static func isAlbum(titled title: String) -> Bool {
        let lowered = title.lowercased()
        let words = Set(lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return !lowered.hasSuffix(" ep") && !lowered.hasSuffix(" - ep") && !lowered.contains("dj mix") && words.isDisjoint(with: notAlbum)
    }

    /// Words in a title that make it something other than an album, for
    /// when the titles decide.
    private static let notAlbum: Set<String> = ["live", "tour", "sessions", "unplugged", "karaoke", "remix", "remixes", "remixed", "instrumentals"]
    /// Words in a closing bracket that make it an edition of an album: not
    /// "version", which a re-recording is ("Taylor's Version").
    private static let editionWords = ["deluxe", "edition", "extended", "expanded", "bonus", "remaster", "anniversary", "complete", "special", "mix"]

    /// The title without the editions in brackets at its end: "Sgt. Pepper's
    /// Lonely Hearts Club Band (Super Deluxe Edition) [2017 Remix]" is
    /// "Sgt. Pepper's Lonely Hearts Club Band".
    public static func plainTitle(_ title: String) -> String {
        var plain = title
        while plain.hasSuffix(")") || plain.hasSuffix("]"), let open = plain.lastIndex(where: { $0 == "(" || $0 == "[" }) {
            let bracket = plain[open...].lowercased()
            guard editionWords.contains(where: bracket.contains) else { break }
            plain = plain[..<open].trimmingCharacters(in: .whitespaces)
        }
        return plain
    }

    private static func isSameDay(_ first: Date?, _ second: Date?) -> Bool {
        guard let first, let second else { return first == nil && second == nil }
        return abs(first.timeIntervalSince(second)) < 24 * 3600
    }
}
