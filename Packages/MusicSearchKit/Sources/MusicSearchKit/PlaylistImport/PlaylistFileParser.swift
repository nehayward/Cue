import Foundation

/// Reads a playlist written out by another app: a CSV from an exporter
/// (Exportify, TuneMyMusic, Soundiiz, a spreadsheet), an M3U playlist, or
/// plain text with one "Artist - Title" a line. A CSV is the way to bring a
/// whole Spotify playlist across, past the 100 songs its share page shows.
public enum PlaylistFileParser {
    public static func parse(_ text: String, fileName: String? = nil) -> ImportedPlaylist? {
        let text = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let fallbackName = fileName.map { ($0 as NSString).deletingPathExtension } ?? "Imported Playlist"
        let fileExtension = fileName.map { ($0 as NSString).pathExtension.lowercased() } ?? ""

        let playlist: (name: String?, tracks: [ImportedTrack])
        if fileExtension.hasPrefix("m3u") || text.hasPrefix("#EXTM3U") {
            playlist = m3u(text)
        } else if let csv = csv(text) {
            playlist = (nil, csv)
        } else {
            playlist = (nil, lines(text))
        }
        guard !playlist.tracks.isEmpty else { return nil }
        return ImportedPlaylist(name: playlist.name ?? fallbackName, source: .file, tracks: playlist.tracks)
    }

    // MARK: - CSV

    /// Header names exporters use, lowercased, most specific first.
    private static let titleColumns = ["track name", "song name", "track title", "song title", "title", "name", "song", "track"]
    private static let artistColumns = ["artist name(s)", "artist names", "artist name", "artist(s)", "artists", "artist", "performer", "album artist"]
    private static let albumColumns = ["album name", "album title", "album"]
    private static let durationColumns = ["duration (ms)", "track duration (ms)", "duration_ms", "duration", "length", "time"]
    private static let isrcColumns = ["isrc"]
    private static let idColumns = ["track uri", "spotify uri", "spotify - id", "spotify id", "uri"]

    static func csv(_ text: String) -> [ImportedTrack]? {
        guard let headerLine = text.split(whereSeparator: \.isNewline).first else { return nil }
        let delimiter: Character = [",", ";", "\t"].max { a, b in
            headerLine.filter { $0 == a }.count < headerLine.filter { $0 == b }.count
        } ?? ","
        let rows = parseRows(text, delimiter: delimiter)
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }),
              let titleColumn = column(in: header, named: titleColumns) else { return nil }
        let artistColumn = column(in: header, named: artistColumns)
        let albumColumn = column(in: header, named: albumColumns)
        let durationColumn = column(in: header, named: durationColumns)
        let isrcColumn = column(in: header, named: isrcColumns)
        let idColumn = column(in: header, named: idColumns)
        let durationInMilliseconds = durationColumn.map { header[$0].contains("ms") } ?? false

        var tracks: [ImportedTrack] = []
        for row in rows.dropFirst() {
            func field(_ index: Int?) -> String? {
                guard let index, index < row.count else { return nil }
                let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            guard let title = field(titleColumn) else { continue }
            tracks.append(ImportedTrack(
                id: tracks.count,
                title: title,
                artists: field(artistColumn).map { [$0] } ?? [],
                album: field(albumColumn),
                duration: field(durationColumn).flatMap { duration($0, milliseconds: durationInMilliseconds) },
                isrc: field(isrcColumn),
                sourceID: field(idColumn)
            ))
        }
        return tracks
    }

    private static func column(in header: [String], named names: [String]) -> Int? {
        for name in names {
            if let index = header.firstIndex(of: name) { return index }
        }
        return nil
    }

    /// Rows of fields, quotes and all: a quoted field keeps its delimiters
    /// and line breaks, and `""` inside one is a quote.
    static func parseRows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        while let character = pending ?? iterator.next() {
            pending = nil
            if quoted {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            quoted = false
                            pending = next
                        }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"" where field.isEmpty:
                quoted = true
            case delimiter:
                row.append(field)
                field = ""
            case "\n", "\r\n", "\r":
                row.append(field)
                field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            default:
                field.append(character)
            }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }

    /// "225868" ms, "225.8" s, "3:45" or "1:02:03".
    static func duration(_ value: String, milliseconds: Bool) -> TimeInterval? {
        if value.contains(":") {
            let parts = value.split(separator: ":").compactMap { Double($0) }
            guard parts.count >= 2 else { return nil }
            return parts.reduce(0) { $0 * 60 + $1 }
        }
        guard let number = Double(value), number > 0 else { return nil }
        // A column that doesn't say: no song is three hours long, so a
        // number that large is milliseconds.
        return milliseconds || number > 10_800 ? number / 1000 : number
    }

    // MARK: - M3U

    static func m3u(_ text: String) -> (name: String?, tracks: [ImportedTrack]) {
        var name: String?
        var tracks: [ImportedTrack] = []
        var info: (duration: TimeInterval?, artist: String?, title: String)?
        var album: String?
        var artist: String?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#PLAYLIST:") {
                name = String(line.dropFirst("#PLAYLIST:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("#EXTINF:") {
                // #EXTINF:225,Artist - Title
                let body = line.dropFirst("#EXTINF:".count)
                let comma = body.firstIndex(of: ",")
                let seconds = comma.flatMap { Double(body[..<$0].split(separator: " ").first ?? "") }
                let label = comma.map { String(body[body.index(after: $0)...]) } ?? ""
                let parts = artistAndTitle(label)
                info = (seconds.flatMap { $0 > 0 ? $0 : nil }, parts.artist, parts.title)
            } else if line.hasPrefix("#EXTALB:") {
                album = String(line.dropFirst("#EXTALB:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("#EXTART:") {
                artist = String(line.dropFirst("#EXTART:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("#") {
                continue
            } else {
                // The entry itself: a path or a URL. Without #EXTINF its file
                // name is all there is to go on.
                let parts = info.map { (artist: $0.artist, title: $0.title) } ?? artistAndTitle(fileTitle(line))
                if !parts.title.isEmpty {
                    tracks.append(ImportedTrack(
                        id: tracks.count,
                        title: parts.title,
                        artists: (parts.artist ?? artist).map { [$0] } ?? [],
                        album: album,
                        duration: info?.duration
                    ))
                }
                info = nil
                album = nil
                artist = nil
            }
        }
        return (name, tracks)
    }

    /// "01 - Queen - Bohemian Rhapsody.mp3" → "Queen - Bohemian Rhapsody".
    private static func fileTitle(_ path: String) -> String {
        let file = (path.removingPercentEncoding ?? path).split(separator: "/").last.map(String.init) ?? path
        var name = (file as NSString).deletingPathExtension
        if let range = name.range(of: #"^\d{1,3}[\s.\-_]+"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Lines

    static func lines(_ text: String) -> [ImportedTrack] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map(artistAndTitle)
            .filter { !$0.title.isEmpty }
            .enumerated()
            .map { index, song in
                ImportedTrack(id: index, title: song.title, artists: song.artist.map { [$0] } ?? [])
            }
    }

    /// "Artist - Title", or the whole line as the title.
    static func artistAndTitle(_ line: String) -> (artist: String?, title: String) {
        let dashes = [" - ", " – ", " — "].compactMap { line.range(of: $0) }
        guard let dash = dashes.min(by: { $0.lowerBound < $1.lowerBound }) else {
            return (nil, line.trimmingCharacters(in: .whitespaces))
        }
        let artist = line[..<dash.lowerBound].trimmingCharacters(in: .whitespaces)
        let title = line[dash.upperBound...].trimmingCharacters(in: .whitespaces)
        if artist.isEmpty || title.isEmpty {
            return (nil, line.trimmingCharacters(in: .whitespaces))
        }
        return (artist, title)
    }
}
