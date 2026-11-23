import Foundation

/// Names for a recording's chapters that say only their place ("Chapter 8",
/// "Track 001"), from a printed edition's contents (`BookContents`).
///
/// A recording's parts aren't always the book's chapters: Audible's reading
/// of The Hobbit by Andy Serkis has 21 parts for 19 chapters, Flies and
/// Spiders read in two and the credits a part of their own. So names aren't
/// handed out by number. Each chapter's pages, at the book's pace in
/// seconds a page, say about how long it's read for, and the parts are
/// grouped in order into chapters so the lengths agree best (squared log
/// error); a run of parts becomes one chapter under its title. The grouping
/// is taken only when every chapter's length agrees closely: the right
/// contents agree within about 10% (25% at worst), parts at random don't
/// get under 40%.
public enum AudiobookChapterNaming {
    /// How far a chapter's length may be from its pages, on average and at
    /// worst, as a log ratio (0.2 is about 22%).
    static let maxError = 0.2
    static let maxWorst = 0.5
    /// How many more parts than chapters a recording may have: each extra
    /// part is a chapter read in two, and with many the grouping could fit
    /// any contents.
    static func extraParts(for chapters: Int) -> Int {
        Swift.max(3, chapters / 3)
    }

    /// Seconds a page, from a children's book to dense small print.
    static let paceRange: ClosedRange<Double> = 24...360

    /// Whether every chapter is named only by its place: "Chapter 8",
    /// "Kapitel 8", "The Hobbit - Track 001", "Part 3", "CD 2" or a bare
    /// number, opening and closing credits aside.
    public static func namesAreNumbers(_ chapters: [AudiobookChapter]) -> Bool {
        let body = trimmingCredits(chapters)
        guard body.count >= 3 else { return false }
        return chapters[body].allSatisfy { isNumbered($0.title) }
    }

    /// `chapters` named by the contents that fit them best, a chapter read
    /// in several parts made one (credits at either end kept as they are);
    /// nil when no contents fit.
    public static func named(_ chapters: [AudiobookChapter], by contents: [BookContents]) -> [AudiobookChapter]? {
        guard namesAreNumbers(chapters) else { return nil }
        let body = trimmingCredits(chapters)
        let parts = Array(chapters[body])
        let fits = contents.compactMap { fit(parts, to: $0) }
        // Titles in capitals only where nothing else fits.
        guard let best = fits.min(by: { ($0.inCapitals ? 1 : 0, $0.error) < ($1.inCapitals ? 1 : 0, $1.error) }) else { return nil }
        let named = Array(chapters[..<body.lowerBound]) + best.chapters + Array(chapters[body.upperBound...])
        return named.enumerated().map { index, chapter in
            AudiobookChapter(id: index, title: chapter.title, start: chapter.start, end: chapter.end)
        }
    }

    /// Contents laid on a recording's parts.
    struct Fit {
        let chapters: [AudiobookChapter]
        /// Root mean square of each chapter's log error.
        let error: Double
        let inCapitals: Bool
    }

    /// The parts grouped into `contents`' chapters, if every chapter but the
    /// last (whose pages aren't known: the book may end with maps, notes or
    /// an index) is about as long as its pages.
    static func fit(_ parts: [AudiobookChapter], to contents: BookContents) -> Fit? {
        let entries = contents.entries
        let count = entries.count
        let durations = parts.map(\.duration)
        guard count >= 3, durations.count >= count, durations.count <= count + extraParts(for: count),
              durations.allSatisfy({ $0 > 0 }) else { return nil }
        let pages = (0..<(count - 1)).map { Double(entries[$0 + 1].page - entries[$0].page) }
        let paged = pages.reduce(0, +)
        guard paged > 0 else { return nil }
        // The pace: a first guess from the whole book, its last chapter
        // taken as long as the average, then from the chapters the grouping
        // gives, until it settles.
        var pace = durations.reduce(0, +) / (paged * Double(count) / Double(count - 1))
        var runs = group(durations, pages: pages, pace: pace)
        for _ in 0..<3 {
            pace = durations[..<runs[count - 1].lowerBound].reduce(0, +) / paged
            runs = group(durations, pages: pages, pace: pace)
        }
        guard paceRange.contains(pace) else { return nil }
        let errors = (0..<(count - 1)).map { index in
            log(durations[runs[index]].reduce(0, +) / (pace * pages[index]))
        }
        let error = (errors.map { $0 * $0 }.reduce(0, +) / Double(errors.count)).squareRoot()
        let worst = errors.map(abs).max() ?? 0
        guard error <= maxError, worst <= maxWorst else { return nil }
        let chapters = zip(entries, runs).enumerated().map { index, pair -> AudiobookChapter in
            let (entry, run) = pair
            return AudiobookChapter(id: index, title: entry.title, start: parts[run.lowerBound].start, end: parts[run.upperBound - 1].end)
        }
        return Fit(chapters: chapters, error: error, inCapitals: contents.isInCapitals)
    }

    /// `durations` split in order into `pages.count + 1` runs of at least
    /// one part each, every run but the last as near `pace` times its pages
    /// as can be.
    static func group(_ durations: [TimeInterval], pages: [Double], pace: Double) -> [Range<Int>] {
        let parts = durations.count
        let runs = pages.count + 1
        var sums: [Double] = [0]
        for duration in durations { sums.append(sums[sums.count - 1] + duration) }
        // cost[run][end]: the least error with `run` runs over the first
        // `end` parts; from[run][end], where that last run starts.
        var cost = Array(repeating: Array(repeating: Double.infinity, count: parts + 1), count: runs + 1)
        var from = Array(repeating: Array(repeating: 0, count: parts + 1), count: runs + 1)
        cost[0][0] = 0
        for run in 1...runs {
            for end in run...(parts - (runs - run)) {
                for start in (run - 1)..<end where cost[run - 1][start] < .infinity {
                    let step: Double
                    if run == runs {
                        step = 0
                    } else {
                        let error = log((sums[end] - sums[start]) / (pace * pages[run - 1]))
                        step = error * error
                    }
                    if cost[run - 1][start] + step < cost[run][end] {
                        cost[run][end] = cost[run - 1][start] + step
                        from[run][end] = start
                    }
                }
            }
        }
        var ranges: [Range<Int>] = []
        var end = parts
        for run in stride(from: runs, to: 0, by: -1) {
            let start = from[run][end]
            ranges.append(start..<end)
            end = start
        }
        return ranges.reversed()
    }

    /// The chapters between any credits at the start and end.
    static func trimmingCredits(_ chapters: [AudiobookChapter]) -> Range<Int> {
        var start = 0
        var end = chapters.count
        while start < end, isCredits(chapters[start].title) { start += 1 }
        while end > start, isCredits(chapters[end - 1].title) { end -= 1 }
        return start..<end
    }

    static func isCredits(_ title: String) -> Bool {
        title.range(of: #"^\s*(?:opening |closing |end )?credits\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isNumbered(_ title: String) -> Bool {
        title.range(of: #"^(?:.*[\s\-–—:_])?(?:chapter|chap\.?|ch\.?|kapitel|chapitre|cap[ií]tulo|capitolo|hoofdstuk|track|part|disc|cd)\s*#?\s*\d+\s*$|^\s*\d+\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
