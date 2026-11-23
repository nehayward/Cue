@testable import MusicSearchKit
import XCTest

final class AudiobookChapterNamingTests: XCTestCase {
    /// Audible's chapters for Andy Serkis's reading of The Hobbit
    /// (1705009050), from Audnexus: 21 parts for the book's 19 chapters,
    /// Flies and Spiders read in two ("Chapter 8" and "Chapter 9") and the
    /// credits a part of their own ("Chapter 21").
    private let serkis = """
    {"brandIntroDurationMs": 3970, "brandOutroDurationMs": 4945, "runtimeLengthMs": 37510826,
     "chapters": [
       {"lengthMs": 3367264, "startOffsetMs": 0, "title": "Chapter 1"},
       {"lengthMs": 1841922, "startOffsetMs": 3367264, "title": "Chapter 2"},
       {"lengthMs": 1098559, "startOffsetMs": 5209186, "title": "Chapter 3"},
       {"lengthMs": 1526363, "startOffsetMs": 6307745, "title": "Chapter 4"},
       {"lengthMs": 2840334, "startOffsetMs": 7834108, "title": "Chapter 5"},
       {"lengthMs": 2421632, "startOffsetMs": 10674442, "title": "Chapter 6"},
       {"lengthMs": 3603736, "startOffsetMs": 13096074, "title": "Chapter 7"},
       {"lengthMs": 2280849, "startOffsetMs": 16699810, "title": "Chapter 8"},
       {"lengthMs": 1600505, "startOffsetMs": 18980659, "title": "Chapter 9"},
       {"lengthMs": 2145964, "startOffsetMs": 20581164, "title": "Chapter 10"},
       {"lengthMs": 1482454, "startOffsetMs": 22727128, "title": "Chapter 11"},
       {"lengthMs": 1151849, "startOffsetMs": 24209582, "title": "Chapter 12"},
       {"lengthMs": 3046411, "startOffsetMs": 25361431, "title": "Chapter 13"},
       {"lengthMs": 1535582, "startOffsetMs": 28407842, "title": "Chapter 14"},
       {"lengthMs": 1329621, "startOffsetMs": 29943424, "title": "Chapter 15"},
       {"lengthMs": 1474908, "startOffsetMs": 31273045, "title": "Chapter 16"},
       {"lengthMs": 821730, "startOffsetMs": 32747953, "title": "Chapter 17"},
       {"lengthMs": 1596395, "startOffsetMs": 33569683, "title": "Chapter 18"},
       {"lengthMs": 1235510, "startOffsetMs": 35166078, "title": "Chapter 19"},
       {"lengthMs": 1059665, "startOffsetMs": 36401588, "title": "Chapter 20"},
       {"lengthMs": 49573, "startOffsetMs": 37461253, "title": "Chapter 21"}
     ]}
    """

    /// Open Library's editions of The Hobbit, cut down: the 1966 edition's
    /// contents (its front matter paged in roman numerals), one listing
    /// titles without pages, the German translation's, and a record that
    /// isn't one.
    private let editions = """
    {"entries": [
      {"key": "/books/OL26456609M", "title": "The Hobbit", "number_of_pages": 300,
       "table_of_contents": [
         {"level": 0, "label": "", "title": "List of Illustrations", "pagenum": "xi"},
         {"level": 0, "label": "", "title": "Note on the Text", "pagenum": "xiii"},
         {"level": 0, "label": "I", "title": "An Unexpected Party", "pagenum": "3"},
         {"level": 0, "label": "II", "title": "Roast Mutton", "pagenum": "27"},
         {"level": 0, "label": "III", "title": "A Short Rest", "pagenum": "43"},
         {"level": 0, "label": "IV", "title": "Over Hill and Under Hill", "pagenum": "52"},
         {"level": 0, "label": "V", "title": "Riddles in the Dark", "pagenum": "65"},
         {"level": 0, "label": "VI", "title": "Out of the Frying-Pan into the Fire", "pagenum": "85"},
         {"level": 0, "label": "VII", "title": "Queer Lodgings", "pagenum": "105"},
         {"level": 0, "label": "VIII", "title": "Flies and Spiders", "pagenum": "130"},
         {"level": 0, "label": "IX", "title": "Barrels Out of Bond", "pagenum": "157"},
         {"level": 0, "label": "X", "title": "A Warm Welcome", "pagenum": "174"},
         {"level": 0, "label": "XI", "title": "On the Doorstep", "pagenum": "186"},
         {"level": 0, "label": "XII", "title": "Inside Information", "pagenum": "195"},
         {"level": 0, "label": "XIII", "title": "Not at Home", "pagenum": "214"},
         {"level": 0, "label": "XIV", "title": "Fire and Water", "pagenum": 225},
         {"level": 0, "label": "XV", "title": "The Gathering of the Clouds", "pagenum": "234"},
         {"level": 0, "label": "XVI", "title": "A Thief in the Night", "pagenum": "244"},
         {"level": 0, "label": "XVII", "title": "The Clouds Burst", "pagenum": "250"},
         {"level": 0, "label": "XVIII", "title": "The Return Journey", "pagenum": "261"},
         {"level": 0, "label": "XIX", "title": "The Last Stage", "pagenum": "269"}
       ]},
      {"key": "/books/OL25652067M", "title": "The Hobbit",
       "table_of_contents": [
         {"level": 0, "label": "", "title": "An unexpected party", "pagenum": ""},
         {"level": 0, "label": "", "title": "Roast mutton", "pagenum": ""},
         {"level": 0, "label": "", "title": "A short rest", "pagenum": ""}
       ]},
      {"key": "/books/OL25159204M", "title": "Der Hobbit",
       "table_of_contents": [
         {"level": 1, "label": "Kapitel I", "title": "Ein unerwartetes Fest", "pagenum": "13"},
         {"level": 1, "label": "Kapitel II", "title": "Hammelbraten", "pagenum": "47"},
         {"level": 1, "label": "Kapitel III", "title": "Eine kurze Rast", "pagenum": "68"}
       ]},
      {"key": "/books/OL1M", "title": 5}
    ]}
    """

    /// The parts as a rip without Audible's branding has them, as the one on
    /// Plex they were found for.
    private func serkisChapters() throws -> [AudiobookChapter] {
        let answer = try JSONDecoder().decode(AudnexusChapters.self, from: Data(serkis.utf8))
        return try XCTUnwrap(answer.chapters(fitting: 37_501.911))
    }

    private func hobbitContents() throws -> [BookContents] {
        let page = try JSONDecoder().decode(OpenLibraryContents.EditionsPage.self, from: Data(editions.utf8))
        let found = try XCTUnwrap(page.entries).compactMap(\.value)
        XCTAssertEqual(found.count, 3, "the record that isn't one is left out")
        return found
            .filter { OpenLibraryContents.titleMatches("The Hobbit", $0.title) }
            .compactMap { BookContents(openLibrary: $0.tableOfContents ?? []) }
    }

    private func chapters(_ titles: [String], length: TimeInterval = 100) -> [AudiobookChapter] {
        titles.enumerated().map { index, title in
            AudiobookChapter(id: index, title: title, start: Double(index) * length, end: Double(index + 1) * length)
        }
    }

    // MARK: - Contents

    func testAnEditionsChaptersWithTheirPages() throws {
        let contents = try hobbitContents()
        // Titles without pages give nothing to go by; "Der Hobbit" is
        // another language's.
        XCTAssertEqual(contents.count, 1)
        let entries = try XCTUnwrap(contents.first).entries
        XCTAssertEqual(entries.count, 19)
        XCTAssertEqual(entries.first, BookContents.Entry(title: "An Unexpected Party", page: 3))
        XCTAssertEqual(entries[13], BookContents.Entry(title: "Fire and Water", page: 225))
        XCTAssertEqual(entries.last, BookContents.Entry(title: "The Last Stage", page: 269))
    }

    func testLinesNotReadAloudAreLeftOut() {
        let contents = BookContents(lines: [
            .init(title: "Contents", page: "v"),
            .init(label: "I", title: "An Unexpected Party", page: "3"),
            .init(label: "II", title: "Roast Mutton.", page: "27"),
            .init(title: "The Trolls", page: "page 38"),
            .init(label: "III", title: "A Short Rest", page: "43"),
            .init(title: "Map of Wilderland", page: "282"),
            .init(title: "Index", page: "290")
        ])
        XCTAssertEqual(contents?.entries.map(\.title), ["An Unexpected Party", "Roast Mutton", "A Short Rest"])
        XCTAssertEqual(contents?.entries.map(\.page), [3, 27, 43])
    }

    func testChaptersUnderParts() {
        // The level with most lines is the chapters; a heading on a
        // chapter's page gives way to it.
        let contents = BookContents(lines: [
            .init(level: 0, title: "Book One", page: "1"),
            .init(level: 1, title: "Part 1", page: "1"),
            .init(level: 1, title: "A Long-expected Party", page: "1"),
            .init(level: 1, title: "The Shadow of the Past", page: "24"),
            .init(level: 1, title: "Three is Company", page: "53"),
            .init(level: 0, title: "Book Two", page: "80"),
            .init(level: 1, title: "Many Meetings", page: "80"),
            // A second list, from the start again.
            .init(level: 1, title: "Appendix A", page: "12")
        ])
        XCTAssertEqual(contents?.entries.map(\.title), ["A Long-expected Party", "The Shadow of the Past", "Three is Company", "Many Meetings"])
    }

    func testTooFewChapters() {
        XCTAssertNil(BookContents(lines: [.init(title: "One", page: "1"), .init(title: "Two", page: "20")]))
    }

    func testEditionsTitledAsTheBook() {
        XCTAssertTrue(OpenLibraryContents.titleMatches("The Hobbit", "The hobbit."))
        XCTAssertTrue(OpenLibraryContents.titleMatches("The Hobbit", "The Hobbit: or There and Back Again"))
        XCTAssertTrue(OpenLibraryContents.titleMatches("The Hobbit", "The Hobbit, or There and Back Again"))
        XCTAssertTrue(OpenLibraryContents.titleMatches("Les Misérables", "Les miserables"))
        XCTAssertFalse(OpenLibraryContents.titleMatches("The Hobbit", "Der Hobbit"))
        XCTAssertFalse(OpenLibraryContents.titleMatches("The Hobbit", "The Hobbits of the Shire"))
        XCTAssertFalse(OpenLibraryContents.titleMatches("The Hobbit", nil))
    }

    // MARK: - Naming

    func testTheHobbitsPartsBecomeItsChapters() throws {
        let named = try XCTUnwrap(AudiobookChapterNaming.named(try serkisChapters(), by: try hobbitContents()))
        XCTAssertEqual(named.count, 19)
        XCTAssertEqual(named.map(\.id), Array(0..<19))
        XCTAssertEqual(named.first?.title, "An Unexpected Party")
        XCTAssertEqual(named.first?.start, 0)
        // Audible's "Chapter 8" and "Chapter 9", one chapter.
        XCTAssertEqual(named[7].title, "Flies and Spiders")
        XCTAssertEqual(named[7].start, 16_695.84, accuracy: 0.01)
        XCTAssertEqual(named[7].end, 20_577.194, accuracy: 0.01)
        XCTAssertEqual(named[8].title, "Barrels Out of Bond")
        XCTAssertEqual(named[8].start, 20_577.194, accuracy: 0.01)
        XCTAssertEqual(named[11].title, "Inside Information")
        // The credits, Audible's "Chapter 21", close the last chapter.
        let last = try XCTUnwrap(named.last)
        XCTAssertEqual(last.title, "The Last Stage")
        XCTAssertEqual(last.start, 36_397.618, accuracy: 0.01)
        XCTAssertEqual(last.end, 37_501.911, accuracy: 0.01)
    }

    func testCreditsStayAsTheyAre() throws {
        let parts = try serkisChapters()
        let end = try XCTUnwrap(parts.last).end
        let chapters = [AudiobookChapter(id: 0, title: "Opening Credits", start: 0, end: 30)]
            + parts.map { AudiobookChapter(id: $0.id + 1, title: $0.title, start: $0.start + 30, end: $0.end + 30) }
            + [AudiobookChapter(id: 22, title: "End Credits", start: end + 30, end: end + 60)]
        let named = try XCTUnwrap(AudiobookChapterNaming.named(chapters, by: try hobbitContents()))
        XCTAssertEqual(named.count, 21)
        XCTAssertEqual(named.map(\.id), Array(0..<21))
        XCTAssertEqual(named.first?.title, "Opening Credits")
        XCTAssertEqual(named[1].title, "An Unexpected Party")
        XCTAssertEqual(named[1].start, 30)
        XCTAssertEqual(named[19].title, "The Last Stage")
        XCTAssertEqual(named.last?.title, "End Credits")
    }

    func testPartsThatDontFitKeepTheirNumbers() throws {
        // The same parts the other way round: no chapter's length agrees
        // with its pages.
        var start: TimeInterval = 0
        let reversed = try serkisChapters().reversed().enumerated().map { index, part -> AudiobookChapter in
            defer { start += part.duration }
            return AudiobookChapter(id: index, title: "Chapter \(index + 1)", start: start, end: start + part.duration)
        }
        XCTAssertNil(AudiobookChapterNaming.named(reversed, by: try hobbitContents()))
    }

    func testFarMorePartsThanChapters() throws {
        // A part every three minutes could be grouped to fit any contents.
        let parts = chapters((1...200).map { "Track \($0)" }, length: 180)
        XCTAssertNil(AudiobookChapterNaming.named(parts, by: try hobbitContents()))
    }

    func testChaptersWithNamesAreLeftAlone() throws {
        let named = try XCTUnwrap(AudiobookChapterNaming.named(try serkisChapters(), by: try hobbitContents()))
        XCTAssertNil(AudiobookChapterNaming.named(named, by: try hobbitContents()))
    }

    func testNamesThatSayOnlyThePlace() {
        XCTAssertTrue(AudiobookChapterNaming.namesAreNumbers(chapters(["Opening Credits", "Chapter 1", "Chapter 2", "Chapter 3", "End Credits"])))
        XCTAssertTrue(AudiobookChapterNaming.namesAreNumbers(chapters(["The Hobbit - Track 001", "The Hobbit - Track 002", "The Hobbit - Track 003"])))
        XCTAssertTrue(AudiobookChapterNaming.namesAreNumbers(chapters(["Kapitel 1", "Kapitel 2", "Kapitel 3"])))
        XCTAssertTrue(AudiobookChapterNaming.namesAreNumbers(chapters(["1", "2", "3"])))
        XCTAssertFalse(AudiobookChapterNaming.namesAreNumbers(chapters(["Prologue", "Chapter 1", "Chapter 2", "Chapter 3"])))
        XCTAssertFalse(AudiobookChapterNaming.namesAreNumbers(chapters(["An Unexpected Party", "Roast Mutton", "A Short Rest"])))
        XCTAssertFalse(AudiobookChapterNaming.namesAreNumbers(chapters(["Chapter 1", "Chapter 2"])))
    }
}
