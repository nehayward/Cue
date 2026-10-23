import Foundation

/// Where a station is, from its description (`Describe.ashx`): the point
/// TuneIn pins it at, when it has one, and the place it names ("Seattle,
/// WA"), which can be looked up on a map when it doesn't.
public struct TuneInPlace: Codable, Hashable, Sendable {
    public var latitude: Double?
    public var longitude: Double?
    public var location: String?

    public init(latitude: Double? = nil, longitude: Double? = nil, location: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.location = location
    }

    /// Both halves of the point, or nil when TuneIn gave none.
    public var coordinate: (latitude: Double, longitude: Double)? {
        guard let latitude, let longitude else { return nil }
        return (latitude, longitude)
    }

    /// What to look `location` up by on a map, best first, for a station
    /// TuneIn gives no point. TuneIn names a city and its state or country,
    /// "Seattle, WA", "Singapore, Singapore", and a market by its cities,
    /// "Seattle-Tacoma, WA", which a geocoder may not know, so the market's
    /// first city follows it. Nothing for a name with no city, "US" or
    /// "Japan": its middle is nowhere near the station, and a Seattle
    /// station TuneIn names only "US" pinned in a field in Nebraska was
    /// where the map framed the stations near you.
    public static func mapQueries(for location: String) -> [String] {
        let location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comma = location.firstIndex(of: ",") else { return [] }
        let city = location[..<comma].trimmingCharacters(in: .whitespaces)
        guard !city.isEmpty else { return [] }

        var queries = [location]
        // "Winston-Salem" is one city, so the whole name goes first.
        let parts = city.split { "-–/".contains($0) }
        if parts.count > 1 {
            let firstCity = parts[0].trimmingCharacters(in: .whitespaces)
            if !firstCity.isEmpty {
                queries.append("\(firstCity)\(location[comma...])")
            }
        }
        return queries
    }

    /// TuneIn's `latlon`, "47.6062,-122.3321". Any run of characters that
    /// can't be in a number separates the two, so a space or a semicolon
    /// reads the same. Nil unless it is exactly two numbers that make a
    /// point on Earth, and not 0,0, which is where a missing point lands.
    static func coordinate(fromLatLon text: String) -> (latitude: Double, longitude: Double)? {
        let numbers = text
            .split { !"0123456789.-+".contains($0) }
            .compactMap { Double($0) }
        guard numbers.count == 2 else { return nil }
        var (latitude, longitude) = (numbers[0], numbers[1])
        // A pair the wrong way round still names one point: a latitude
        // can't pass 90.
        if abs(latitude) > 90, abs(longitude) <= 90 {
            swap(&latitude, &longitude)
        }
        guard abs(latitude) <= 90, abs(longitude) <= 180,
              latitude != 0 || longitude != 0 else { return nil }
        return (latitude, longitude)
    }
}
