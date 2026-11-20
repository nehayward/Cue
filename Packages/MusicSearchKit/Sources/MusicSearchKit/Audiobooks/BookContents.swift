import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A printed edition's table of contents: each chapter's title and the page
/// it starts on. Page numbers are what make it usable for an audiobook:
/// how many pages a chapter runs is about how long it's read for, which is
/// how `AudiobookChapterNaming` finds the chapters among a recording's
/// numbered parts.
public struct BookContents: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        public let title: String
        /// The page it starts on.
        public let page: Int

        public init(title: String, page: Int) {
            self.title = title
            self.page = page
        }
    }

    /// The chapters, in order, each starting on a later page than the one
    /// before.
    public let entries: [Entry]

    /// Nil for fewer than three chapters, or pages that don't run forward.
    public init?(entries: [Entry]) {
        guard entries.count >= 3, zip(entries, entries.dropFirst()).allSatisfy({ $0.page < $1.page }) else { return nil }
        self.entries = entries
    }

    /// Whether the titles are in capitals throughout, as some editions'
    /// contents are: another edition's are better to show.
    var isInCapitals: Bool {
        entries.allSatisfy { $0.title == $0.title.uppercased() && $0.title.contains(where: \.isLetter) }
    }
}

// MARK: - Open Library

/// Open Library's printed editions of a book, for their tables of contents
/// (`openlibrary.org/works/<id>/editions.json`): free, with no key. Many
/// editions list none, some list titles without pages; those with pages are
/// kept (`BookContents(openLibrary:)`).
public enum OpenLibraryContents {
    /// The contents of the editions of `title` by `author` titled as the
    /// book is (so in its language: "Der Hobbit" isn't "The Hobbit"), each
    /// with page numbers; empty when none has them, nil when Open Library
    /// couldn't be asked.
    public static func contents(title: String, author: String?) async -> [BookContents]? {
        let query = AudibleCatalog.searchTitle(title)
        guard !query.isEmpty else { return [] }
        var works = await search(title: query, author: author)
        // An author named another way ("Tolkien, J. R. R.") finds nothing:
        // the title alone, whose editions are checked by title and length.
        if works?.isEmpty == true, author?.isEmpty == false {
            works = await search(title: query, author: nil)
        }
        guard let works else { return nil }
        // The work of that title, before one whose title only starts with
        // it ("The Hobbit & The Lord of the Rings").
        let wanted = plain(query)
        guard let work = works.first(where: { plain(AudibleCatalog.searchTitle($0.title ?? "")) == wanted })
                ?? works.first(where: { titleMatches(query, $0.title) }) ?? works.first,
              let printed = await editions(ofWork: work.key) else {
            return works.isEmpty ? [] : nil
        }
        return printed
            .filter { titleMatches(query, $0.title) }
            .compactMap { BookContents(openLibrary: $0.tableOfContents ?? []) }
    }

    struct SearchPage: Decodable {
        struct Work: Decodable {
            /// "/works/OL27482W".
            let key: String
            let title: String?
        }

        let docs: [Lenient<Work>]?
    }

    struct EditionsPage: Decodable {
        let entries: [Lenient<Edition>]?
    }

    struct Edition: Decodable {
        let title: String?
        let tableOfContents: [Lenient<ContentsItem>]?

        enum CodingKeys: String, CodingKey {
            case title
            case tableOfContents = "table_of_contents"
        }
    }

    /// One line of an edition's contents: `{"level": 0, "label": "VIII",
    /// "title": "Flies and Spiders", "pagenum": "130"}`, any of it missing.
    struct ContentsItem: Decodable {
        var level = 0
        var label = ""
        var title = ""
        var page = ""

        enum CodingKeys: String, CodingKey {
            case level, label, title
            case page = "pagenum"
        }

        init(level: Int = 0, label: String = "", title: String, page: String) {
            self.level = level
            self.label = label
            self.title = title
            self.page = page
        }

        init(from decoder: Decoder) throws {
            // A line of plain text, in some older records.
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                title = text
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            level = (try? container.decodeIfPresent(Int.self, forKey: .level)) ?? 0
            label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? ""
            title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
            if let text = try? container.decodeIfPresent(String.self, forKey: .page) {
                page = text
            } else if let number = try? container.decodeIfPresent(Int.self, forKey: .page) {
                page = String(number)
            }
        }
    }

    /// The works Open Library finds for `title` by `author`, most relevant
    /// first; nil when it couldn't be asked.
    static func search(title: String, author: String?) async -> [SearchPage.Work]? {
        var components = URLComponents(string: "https://openlibrary.org/search.json")
        var query = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "fields", value: "key,title")
        ]
        if let author, !author.isEmpty {
            query.append(URLQueryItem(name: "author", value: author))
        }
        components?.queryItems = query
        guard let url = components?.url, let page = await fetch(SearchPage.self, from: url) else { return nil }
        return (page.docs ?? []).compactMap(\.value)
    }

    /// Every edition of `work` ("/works/OL27482W"), up to a thousand; nil
    /// when Open Library couldn't be asked.
    static func editions(ofWork work: String) async -> [Edition]? {
        guard work.hasPrefix("/works/"),
              var components = URLComponents(string: "https://openlibrary.org\(work)/editions.json") else { return nil }
        components.queryItems = [URLQueryItem(name: "limit", value: "1000")]
        guard let url = components.url, let page = await fetch(EditionsPage.self, from: url) else { return nil }
        return (page.entries ?? []).compactMap(\.value)
    }

    private static func fetch<Page: Decodable>(_ type: Page.Type, from url: URL) async -> Page? {
        var request = URLRequest(url: url)
        // A popular book's editions run to a megabyte, and Open Library is
        // slow to send them.
        request.timeoutInterval = 30
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Page.self, from: data)
    }

    /// Whether an edition or work titled `title` is the book searched for as
    /// `query`: the same title before any subtitle ("The Hobbit: or There and
    /// Back Again"), or the title with more after it ("The Hobbit, or There
    /// and Back Again"), ignoring case, accents and punctuation.
    static func titleMatches(_ query: String, _ title: String?) -> Bool {
        guard let title else { return false }
        let wanted = plain(query)
        guard !wanted.isEmpty else { return false }
        return plain(AudibleCatalog.searchTitle(title)) == wanted || plain(title).hasPrefix(wanted + " ")
    }

    /// Lower case, with no accents, and words of letters and digits only.
    public static func plain(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

extension BookContents {
    /// An Open Library edition's contents, as chapters with pages: the
    /// lines at the level with most of them paged (chapters, where an
    /// edition also lists its parts), with an arabic page number, that a
    /// reading would have (not the list of illustrations, maps or the
    /// index), a part's heading giving way to the chapter on its page. Nil
    /// for fewer than three.
    init?(openLibrary items: [Lenient<OpenLibraryContents.ContentsItem>]) {
        self.init(lines: items.compactMap(\.value))
    }

    init?(lines items: [OpenLibraryContents.ContentsItem]) {
        let paged = items.compactMap { item -> (level: Int, entry: Entry)? in
            let page = item.page.trimmingCharacters(in: .whitespaces)
            guard !page.isEmpty, page.allSatisfy(\.isASCII), let number = Int(page), number >= 0 else { return nil }
            let title = Self.cleaned(item.title.isEmpty ? item.label : item.title)
            guard !title.isEmpty, !Self.isUnread(title) else { return nil }
            return (item.level, Entry(title: title, page: number))
        }
        var counts: [Int: Int] = [:]
        for line in paged { counts[line.level, default: 0] += 1 }
        guard let level = counts.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value })?.key else { return nil }
        var entries: [Entry] = []
        for line in paged where line.level == level {
            if let last = entries.last {
                if line.entry.page == last.page {
                    entries[entries.count - 1] = line.entry
                    continue
                }
                // A second list, numbered again from the start.
                guard line.entry.page > last.page else { continue }
            }
            entries.append(line.entry)
        }
        self.init(entries: entries)
    }

    /// The title without the spaces and full stop records often carry.
    private static func cleaned(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(".") || text.hasSuffix(",") || text.hasSuffix(";") {
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    /// Whether a line names something printed but not read aloud.
    static func isUnread(_ title: String) -> Bool {
        title.range(of: #"^(?:a\s+)?(?:note on the text|(?:table of )?contents|(?:list of )?(?:illustrations|maps|plates|figures)|maps?\b.*|index|acknowledge?ments|copyright.*|dedication|about the (?:author|authors|illustrator).*|also by.*|bibliography|further reading|frontispiece|(?:half )?title page|half title|cover)$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// A value decoded where it can be, else nil, so one odd record in a list
/// doesn't fail the whole list.
struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
